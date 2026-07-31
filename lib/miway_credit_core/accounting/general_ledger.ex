defmodule MiwayCreditCore.Accounting.GeneralLedger do
  @moduledoc """
  The real double-entry ledger — `JournalEntry` + `JournalLine` — sitting
  alongside `AccountingEntry` (which stays the source of truth for a
  `LoanAccount`'s cached `outstanding_balance`) as the financial-statement
  layer. Every operation that already posts an `AccountingEntry`
  (disbursement, repayment, reversal, write-off, penalty accrual) also
  posts a balanced journal entry here, in the same `Ecto.Multi`.

  `post_journal_entry/3` refuses to insert anything unbalanced —
  `sum(debits) == sum(credits)` is asserted before any row is written,
  so the critical invariant (see `trial_balance/1`) holds by
  construction: the only way a `JournalLine` gets created is through
  this one function. Never edited or deleted once posted — a mistaken
  entry is reversed (`post_reversal/3`), which posts a new
  entry, never touches the old one.
  """

  import Ecto.Query
  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.Accounting.{Account, JournalEntry, JournalLine}
  alias MiwayCreditCore.Accounts.Scope

  @chart_of_accounts [
    %{code: "1000", name: "Cash", account_type: "asset"},
    %{code: "1010", name: "Bank", account_type: "asset"},
    %{code: "1020", name: "Mobile Money", account_type: "asset"},
    %{code: "1030", name: "Suspense", account_type: "asset"},
    %{code: "1100", name: "Loans Receivable", account_type: "asset"},
    %{code: "4000", name: "Interest Income", account_type: "income"},
    %{code: "4100", name: "Fee Income", account_type: "income"},
    %{code: "4200", name: "Penalty Income", account_type: "income"},
    %{code: "5000", name: "Bad Debt Expense", account_type: "expense"}
  ]

  @cash_type_codes ~w(1000 1010 1020 1030)

  @doc "The chart of accounts (9 accounts) for a fresh organisation."
  def seed_chart_of_accounts(organisation_id) do
    Enum.reduce_while(@chart_of_accounts, {:ok, []}, fn attrs, {:ok, inserted} ->
      %Account{}
      |> Account.changeset(Map.put(attrs, :organisation_id, organisation_id))
      |> Repo.insert()
      |> case do
        {:ok, account} -> {:cont, {:ok, [account | inserted]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  @doc "The cash-side account code for a payment/disbursement method — cash, bank-like, mobile money, or an honest Suspense bucket for anything uncategorized."
  def cash_account_code("cash"), do: "1000"

  def cash_account_code(method) when method in ["bank_transfer", "cheque", "payroll_deduction"],
    do: "1010"

  def cash_account_code("mobile_money"), do: "1020"
  def cash_account_code(_other), do: "1030"

  @doc """
  Posts one balanced journal entry into `multi` under `key` (the
  header) and `:"\#{key}_lines"` (the lines). `attrs.lines` is a list of
  `%{account_code: code, debit: amount}` or `%{account_code: code,
  credit: amount}` (or `:account_id` instead of `:account_code`, used
  by `post_reversal/3`). Refuses — via `Ecto.Multi.error/3`, no insert
  attempted — unless the debits and credits sum to the same total.
  """
  def post_journal_entry(multi, key, attrs) do
    lines = Enum.reject(attrs.lines, &zero_line?/1)
    total_debits = sum_side(lines, :debit)
    total_credits = sum_side(lines, :credit)

    cond do
      # A caller passed only zero-amount lines (e.g. a zero-percent fee) —
      # skip posting an empty/no-op journal entry entirely, same
      # "zero-fee products post nothing" convention already used
      # elsewhere in this codebase, rather than writing a header with no
      # lines under it.
      lines == [] ->
        multi

      not Decimal.equal?(total_debits, total_credits) ->
        Ecto.Multi.error(multi, key, {:unbalanced_journal_entry, total_debits, total_credits})

      true ->
        multi
        |> Ecto.Multi.insert(
          key,
          JournalEntry.changeset(%JournalEntry{}, %{
            organisation_id: attrs.organisation_id,
            description: attrs.description,
            source_type: attrs.source_type,
            source_id: Map.get(attrs, :source_id),
            occurred_at: attrs.occurred_at,
            recorded_by_id: Map.get(attrs, :recorded_by_id)
          })
        )
        |> Ecto.Multi.run(lines_key(key), fn repo, changes ->
          entry = Map.fetch!(changes, key)
          account_ids = account_ids_by_code(repo, attrs.organisation_id)

          Enum.each(lines, fn line ->
            account_id = Map.get(line, :account_id) || Map.fetch!(account_ids, line.account_code)

            %JournalLine{}
            |> JournalLine.changeset(%{
              organisation_id: attrs.organisation_id,
              journal_entry_id: entry.id,
              account_id: account_id,
              debit_amount: Map.get(line, :debit),
              credit_amount: Map.get(line, :credit)
            })
            |> repo.insert!()
          end)

          {:ok, :posted}
        end)
    end
  end

  @doc """
  Reverses every `JournalLine` ever posted under `source_type`/
  `source_id` — nets debit/credit per account, then posts one new
  balanced entry with the negated net per account (an account whose
  net is already zero is skipped). Generic on purpose: works whether
  the original posting was one journal entry (a repayment) or several
  (a disbursement plus an origination fee plus any penalty accrued
  since) — no need to hand-reconstruct what was originally posted.
  """
  def post_reversal(multi, key, attrs) do
    multi
    |> Ecto.Multi.run(lookup_key(key), fn repo, _changes ->
      {:ok, net_lines_for_source(repo, attrs.organisation_id, attrs.source_type, attrs.source_id)}
    end)
    |> Ecto.Multi.merge(fn changes ->
      lines =
        changes
        |> Map.fetch!(lookup_key(key))
        |> reversal_lines()

      case lines do
        [] ->
          Ecto.Multi.new()

        lines ->
          post_journal_entry(Ecto.Multi.new(), key, %{
            organisation_id: attrs.organisation_id,
            description: attrs.description,
            source_type: attrs.source_type,
            source_id: attrs.source_id,
            occurred_at: attrs.occurred_at,
            recorded_by_id: Map.get(attrs, :recorded_by_id),
            lines: lines
          })
      end
    end)
  end

  @doc "Total debits/credits across every JournalLine in scope — the checkable form of the critical invariant."
  def trial_balance(%Scope{} = scope) do
    total_debits =
      JournalLine
      |> scope_organisation(scope)
      |> select([jl], coalesce(sum(jl.debit_amount), ^Decimal.new("0.00")))
      |> Repo.one()

    total_credits =
      JournalLine
      |> scope_organisation(scope)
      |> select([jl], coalesce(sum(jl.credit_amount), ^Decimal.new("0.00")))
      |> Repo.one()

    %{
      total_debits: total_debits,
      total_credits: total_credits,
      balanced?: Decimal.equal?(total_debits, total_credits)
    }
  end

  @doc "Net balance (debit - credit) per cash-type account (Cash/Bank/Mobile Money/Suspense) — the reconciliation baseline staff check against a real bank/mobile-money statement."
  def cash_position(%Scope{} = scope) do
    Account
    |> scope_organisation(scope)
    |> where([a], a.code in ^@cash_type_codes)
    |> join(:left, [a], jl in JournalLine, on: jl.account_id == a.id)
    |> group_by([a], [a.organisation_id, a.code, a.name])
    |> order_by([a], [a.organisation_id, a.code])
    |> select([a, jl], %{
      organisation_id: a.organisation_id,
      code: a.code,
      name: a.name,
      balance: coalesce(sum(jl.debit_amount), 0) - coalesce(sum(jl.credit_amount), 0)
    })
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp sum_side(lines, side) do
    lines
    |> Enum.map(&Map.get(&1, side))
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)
  end

  defp zero_line?(line) do
    value = Map.get(line, :debit) || Map.get(line, :credit) || Decimal.new("0")
    Decimal.equal?(value, Decimal.new("0"))
  end

  defp lines_key(key), do: :"#{key}_lines"
  defp lookup_key(key), do: :"#{key}_lookup"

  defp account_ids_by_code(repo, organisation_id) do
    Account
    |> where([a], a.organisation_id == ^organisation_id)
    |> select([a], {a.code, a.id})
    |> repo.all()
    |> Map.new()
  end

  defp net_lines_for_source(repo, organisation_id, source_type, source_id) do
    from(jl in JournalLine,
      join: je in JournalEntry,
      on: je.id == jl.journal_entry_id,
      where:
        je.organisation_id == ^organisation_id and je.source_type == ^source_type and
          je.source_id == ^source_id,
      select: {jl.account_id, jl.debit_amount, jl.credit_amount}
    )
    |> repo.all()
    |> Enum.reduce(%{}, fn {account_id, debit, credit}, acc ->
      delta = Decimal.sub(debit || Decimal.new("0"), credit || Decimal.new("0"))
      Map.update(acc, account_id, delta, &Decimal.add(&1, delta))
    end)
  end

  defp reversal_lines(net_by_account) do
    net_by_account
    |> Enum.reject(fn {_account_id, net} -> Decimal.equal?(net, Decimal.new("0")) end)
    |> Enum.map(fn {account_id, net} ->
      if Decimal.compare(net, Decimal.new("0")) == :gt do
        %{account_id: account_id, credit: net}
      else
        %{account_id: account_id, debit: Decimal.negate(net)}
      end
    end)
  end

  defp scope_organisation(query, %Scope{organisation_id: :all}), do: query

  defp scope_organisation(query, %Scope{organisation_id: organisation_id}) do
    where(query, organisation_id: ^organisation_id)
  end
end
