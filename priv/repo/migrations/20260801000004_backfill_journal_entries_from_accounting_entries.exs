defmodule MiwayCreditCore.Repo.Migrations.BackfillJournalEntriesFromAccountingEntries.JournalEntryRow do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "journal_entries" do
    field :organisation_id, :binary_id
    field :description, :string
    field :source_type, :string
    field :source_id, :binary_id
    field :occurred_at, :utc_datetime
    field :recorded_by_id, :integer
    timestamps(updated_at: false)
  end
end

defmodule MiwayCreditCore.Repo.Migrations.BackfillJournalEntriesFromAccountingEntries.JournalLineRow do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "journal_lines" do
    field :organisation_id, :binary_id
    field :journal_entry_id, :binary_id
    field :account_id, :binary_id
    field :debit_amount, :decimal
    field :credit_amount, :decimal
    timestamps(updated_at: false)
  end
end

defmodule MiwayCreditCore.Repo.Migrations.BackfillJournalEntriesFromAccountingEntries do
  @moduledoc """
  Step 14: gives every pre-existing `AccountingEntry` row a matching
  balanced `JournalEntry`/`JournalLine` pair. Unlike Step 12's
  `contract_reference` backfill (where the true historical value was
  genuinely unrecoverable), every `AccountingEntry` already carries
  enough — `entry_type`, `amount`, `loan_account_id`, `source_type`,
  `source_id` — plus `loan_accounts.principal_amount`/
  `disbursement_method` and `payment_transactions.method` (read via
  raw, schema-less queries) to derive its exact debit/credit split
  deterministically. No `InterestCalculator` or `GeneralLedger` call —
  the account-code list and reversal logic are duplicated here on
  purpose, so this migration stays a self-contained, replayable
  snapshot independent of future application-code changes (same
  convention Step 12's raw-SQL backfill already established).

  Processed in `inserted_at` order — a reversal entry's generic
  "net whatever was already posted under this source and negate it"
  logic depends on the entries it's reversing already having their
  journal lines inserted earlier in this same run.
  """

  use Ecto.Migration
  import Ecto.Query

  alias MiwayCreditCore.Repo.Migrations.BackfillJournalEntriesFromAccountingEntries.{JournalEntryRow, JournalLineRow}

  def up do
    repo = repo()
    account_ids = account_ids_by_org_and_code(repo)

    entries =
      repo.all(
        from(e in "accounting_entries",
          order_by: [asc: e.inserted_at],
          select: %{
            entry_type: e.entry_type,
            amount: e.amount,
            organisation_id: e.organisation_id,
            loan_account_id: e.loan_account_id,
            source_type: e.source_type,
            source_id: e.source_id,
            description: e.description,
            occurred_at: e.occurred_at,
            recorded_by_id: e.recorded_by_id
          }
        )
      )

    Enum.each(entries, &backfill(repo, &1, account_ids))
  end

  def down do
    execute("DELETE FROM journal_lines")
    execute("DELETE FROM journal_entries")
  end

  # --- entry_type -> Dr/Cr shape, mirroring the call-site logic exactly ---

  defp backfill(repo, %{entry_type: "disbursement"} = e, account_ids) do
    %{principal_amount: principal, disbursement_method: method} =
      repo.one!(
        from(a in "loan_accounts",
          where: a.id == ^e.loan_account_id,
          select: %{principal_amount: a.principal_amount, disbursement_method: a.disbursement_method}
        )
      )

    interest = Decimal.sub(e.amount, principal)

    post(repo, e, account_ids, [
      {"1100", :debit, e.amount},
      {cash_account_code(method), :credit, principal},
      {"4000", :credit, interest}
    ])
  end

  defp backfill(repo, %{entry_type: "fee"} = e, account_ids) do
    post(repo, e, account_ids, [{"1100", :debit, e.amount}, {"4100", :credit, e.amount}])
  end

  defp backfill(repo, %{entry_type: "penalty"} = e, account_ids) do
    post(repo, e, account_ids, [{"1100", :debit, e.amount}, {"4200", :credit, e.amount}])
  end

  defp backfill(repo, %{entry_type: "repayment"} = e, account_ids) do
    method = repo.one!(from(t in "payment_transactions", where: t.id == ^e.source_id, select: t.method))
    payable = Decimal.abs(e.amount)

    post(repo, e, account_ids, [{cash_account_code(method), :debit, payable}, {"1100", :credit, payable}])
  end

  defp backfill(repo, %{entry_type: "reversal", source_type: "payment_transaction"} = e, account_ids) do
    reverse_source(repo, e, account_ids, "payment_transaction", e.source_id)
  end

  defp backfill(repo, %{entry_type: "reversal", source_type: "manual_adjustment"} = e, account_ids) do
    reverse_source(repo, e, account_ids, "loan_account", e.loan_account_id)
  end

  defp backfill(repo, %{entry_type: "write_off"} = e, account_ids) do
    amount = Decimal.abs(e.amount)
    post(repo, e, account_ids, [{"5000", :debit, amount}, {"1100", :credit, amount}])
  end

  # Generic reversal: nets whatever's already been posted (earlier in
  # this same migration run) under `source_type`/`source_id`, then
  # posts the exact negation — the same trick
  # GeneralLedger.post_reversal/3 uses at runtime, so a
  # reverse_disbursement backfill correctly unwinds disbursement + fee
  # + any penalty together without hand-reconstructing the split.
  defp reverse_source(repo, e, _account_ids, source_type, source_id) do
    net =
      repo.all(
        from(jl in "journal_lines",
          join: je in "journal_entries",
          on: je.id == jl.journal_entry_id,
          where: je.source_type == ^source_type and je.source_id == ^source_id,
          select: {jl.account_id, jl.debit_amount, jl.credit_amount}
        )
      )
      |> Enum.reduce(%{}, fn {account_id, debit, credit}, acc ->
        delta = Decimal.sub(debit || Decimal.new("0"), credit || Decimal.new("0"))
        Map.update(acc, account_id, delta, &Decimal.add(&1, delta))
      end)

    lines =
      net
      |> Enum.reject(fn {_id, n} -> Decimal.equal?(n, Decimal.new("0")) end)
      |> Enum.map(fn {account_id, n} ->
        if Decimal.compare(n, Decimal.new("0")) == :gt do
          {account_id, :credit, n}
        else
          {account_id, :debit, Decimal.negate(n)}
        end
      end)

    post_by_account_id(repo, e, lines)
  end

  # --- shared posting helpers ---

  defp post(repo, e, account_ids, lines) do
    lines =
      lines
      |> Enum.reject(fn {_code, _side, amount} -> Decimal.equal?(amount, Decimal.new("0")) end)
      |> Enum.map(fn {code, side, amount} -> {Map.fetch!(account_ids, {e.organisation_id, code}), side, amount} end)

    post_by_account_id(repo, e, lines)
  end

  defp post_by_account_id(_repo, _e, []), do: :ok

  defp post_by_account_id(repo, e, lines) do
    # Raw (schema-less) selects hand back binary_id/uuid columns
    # already dumped to their 16-byte binary form — Ecto's own
    # Changeset/insert path expects the loadable string form for a
    # :binary_id field (it dumps again on insert), so these need
    # loading back first.
    {:ok, entry} =
      %JournalEntryRow{}
      |> Ecto.Changeset.change(%{
        organisation_id: load_uuid!(e.organisation_id),
        description: e.description,
        source_type: e.source_type,
        source_id: load_uuid(e.source_id),
        occurred_at: to_utc_datetime(e.occurred_at),
        recorded_by_id: e.recorded_by_id
      })
      |> repo.insert()

    Enum.each(lines, fn {account_id, side, amount} ->
      attrs =
        %{organisation_id: load_uuid!(e.organisation_id), journal_entry_id: entry.id, account_id: load_uuid!(account_id)}
        |> Map.put(side_field(side), amount)

      %JournalLineRow{}
      |> Ecto.Changeset.change(attrs)
      |> repo.insert!()
    end)
  end

  defp side_field(:debit), do: :debit_amount
  defp side_field(:credit), do: :credit_amount

  defp load_uuid(nil), do: nil
  defp load_uuid(binary), do: load_uuid!(binary)
  defp load_uuid!(binary), do: Ecto.UUID.load!(binary)

  # Raw (schema-less) selects decode a `timestamp` column to a
  # NaiveDateTime; JournalEntryRow's occurred_at is :utc_datetime.
  # accounting_entries.occurred_at is always already-UTC in practice
  # (every writer uses DateTime.utc_now/0), so this is a type
  # relabeling, not a real timezone conversion.
  defp to_utc_datetime(%NaiveDateTime{} = naive), do: naive |> DateTime.from_naive!("Etc/UTC") |> DateTime.truncate(:second)
  defp to_utc_datetime(%DateTime{} = datetime), do: DateTime.truncate(datetime, :second)

  defp cash_account_code("cash"), do: "1000"
  defp cash_account_code(method) when method in ["bank_transfer", "cheque", "payroll_deduction"], do: "1010"
  defp cash_account_code("mobile_money"), do: "1020"
  defp cash_account_code(_other), do: "1030"

  defp account_ids_by_org_and_code(repo) do
    repo.all(from(a in "accounts", select: {a.organisation_id, a.code, a.id}))
    |> Map.new(fn {organisation_id, code, id} -> {{organisation_id, code}, id} end)
  end
end
