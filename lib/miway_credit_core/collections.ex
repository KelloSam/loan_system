defmodule MiwayCreditCore.Collections do
  @moduledoc """
  The org's active effort to collect on delinquent loans: cases,
  communication history/follow-ups, promises to pay, restructuring
  requests, and write-off requests. A `CollectionCase` opens
  automatically the first time an account has any overdue installment
  (`ensure_case_opened/2`, called from
  `MiwayCreditCore.Lending.Schedule.flip_to_overdue/1`) — collections
  work starts the moment arrears exist, not behind some extra severity
  threshold invented from nothing.

  Restructuring and write-off both go through a real request/approve
  workflow — the approver can never be the requester
  (`maker_checker_violation`), same guard
  `MiwayCreditCore.Applications.check_separation_of_duties/3` already
  uses for application approval.
  """

  import Ecto.Query
  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.Collections.{CollectionCase, CollectionActivity, PromiseToPay, RestructuringRequest, WriteOffRequest}
  alias MiwayCreditCore.Lending
  alias MiwayCreditCore.Lending.{LoanAccount, RepaymentScheduleInstallment, InterestCalculator}
  alias MiwayCreditCore.Payments.PaymentTransaction
  alias MiwayCreditCore.Accounting.AccountingEntry
  alias MiwayCreditCore.Accounts.Scope

  @arrears_buckets [
    {0, "current"},
    {30, "1_30_days"},
    {60, "31_60_days"},
    {90, "61_90_days"}
  ]

  @doc """
  Buckets a days-past-due number into an arrears classification —
  plain day-range names (not banking/regulatory jargon like
  "substandard"/"doubtful", which are real fixed terms in some
  jurisdictions this system hasn't been confirmed to need to match).
  """
  def classify_arrears(days_past_due) when is_integer(days_past_due) do
    case Enum.find(@arrears_buckets, fn {max_days, _label} -> days_past_due <= max_days end) do
      {_max_days, label} -> label
      nil -> "over_90_days"
    end
  end

  def list_cases_for_account(%Scope{} = scope, loan_account_id) do
    CollectionCase
    |> scope_organisation(scope)
    |> where([c], c.loan_account_id == ^loan_account_id)
    |> order_by([c], desc: c.opened_at)
    |> Repo.all()
  end

  def get_open_case_for_account(%Scope{} = scope, loan_account_id) do
    CollectionCase
    |> scope_organisation(scope)
    |> where([c], c.loan_account_id == ^loan_account_id and c.status != "closed")
    |> Repo.one()
  end

  def get_case!(%Scope{} = scope, id) do
    CollectionCase
    |> scope_organisation(scope)
    |> Repo.get!(id)
  end

  @doc """
  Opens a `CollectionCase` for `account` if none is currently open —
  idempotent, so calling this on every overdue-sweep tick for an
  account that already has a case is a no-op. No `admin_id`: this is
  system-triggered, same "no actor" convention already used for
  penalty-accrual ledger entries.
  """
  def ensure_case_opened(repo \\ Repo, %LoanAccount{} = account) do
    already_open? =
      CollectionCase
      |> where([c], c.loan_account_id == ^account.id and c.status != "closed")
      |> repo.exists?()

    if already_open? do
      {:ok, :already_open}
    else
      %CollectionCase{}
      |> CollectionCase.changeset(%{
        organisation_id: account.organisation_id,
        loan_account_id: account.id,
        customer_id: account.customer_id,
        status: "open",
        recovery_status: "none",
        opened_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> repo.insert()
    end
  end

  @doc "Moves a case to in_progress/escalated, or closes it with a reason."
  def escalate_case(%CollectionCase{} = collection_case) do
    collection_case
    |> CollectionCase.changeset(%{status: "escalated"})
    |> Repo.update()
  end

  def close_case(%CollectionCase{} = collection_case, reason) do
    collection_case
    |> CollectionCase.changeset(%{
      status: "closed",
      close_reason: reason,
      closed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  @doc """
  Updates a case's recovery status. Setting it to `"legal_action"`
  also flips the loan account to `"defaulted"` in the same
  transaction — the first real use of that status value, which has
  existed since Step 9 but nothing has ever set.
  """
  def set_recovery_status(%CollectionCase{} = collection_case, recovery_status, _admin_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:case, CollectionCase.changeset(collection_case, %{recovery_status: recovery_status}))
    |> Ecto.Multi.run(:account, fn repo, _changes ->
      if recovery_status == "legal_action" do
        account = repo.get!(LoanAccount, collection_case.loan_account_id)
        account |> LoanAccount.changeset(%{status: "defaulted"}) |> repo.update()
      else
        {:ok, nil}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{case: updated_case}} -> {:ok, updated_case}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  def list_activities_for_case(%Scope{} = scope, collection_case_id) do
    CollectionActivity
    |> scope_organisation(scope)
    |> where([a], a.collection_case_id == ^collection_case_id)
    |> order_by([a], desc: a.occurred_at)
    |> Repo.all()
  end

  @doc "Records one contact attempt/note against a case — communication history and, when follow_up_date is set, a pending follow-up."
  def log_activity(%CollectionCase{} = collection_case, attrs) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.put("organisation_id", collection_case.organisation_id)
      |> Map.put("collection_case_id", collection_case.id)

    %CollectionActivity{}
    |> CollectionActivity.changeset(attrs)
    |> Repo.insert()
  end

  def list_promises_for_case(%Scope{} = scope, collection_case_id) do
    PromiseToPay
    |> scope_organisation(scope)
    |> where([p], p.collection_case_id == ^collection_case_id)
    |> order_by([p], desc: p.promised_date)
    |> Repo.all()
  end

  def record_promise(%CollectionCase{} = collection_case, attrs) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.put("organisation_id", collection_case.organisation_id)
      |> Map.put("collection_case_id", collection_case.id)

    %PromiseToPay{}
    |> PromiseToPay.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Evaluates every pending promise whose promised_date has passed —
  called from the existing `ArrearsScheduler` tick, alongside
  `Lending.mark_overdue_installments/0`, rather than a second
  background process for a near-identical cadence. Returns the count
  evaluated.
  """
  def evaluate_promises do
    today = Date.utc_today()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    due_promises =
      PromiseToPay
      |> where([p], p.status == "pending" and p.promised_date < ^today)
      |> preload(:collection_case)
      |> Repo.all()

    Enum.each(due_promises, fn promise ->
      kept? =
        PaymentTransaction
        |> where([t], t.loan_account_id == ^promise.collection_case.loan_account_id)
        |> where([t], t.status == "posted")
        |> where([t], t.inserted_at >= ^promise.inserted_at)
        |> where([t], t.amount >= ^promise.promised_amount)
        |> Repo.exists?()

      promise
      |> PromiseToPay.evaluation_changeset(%{status: if(kept?, do: "kept", else: "broken"), evaluated_at: now})
      |> Repo.update!()
    end)

    length(due_promises)
  end

  def list_restructuring_requests_for_account(%Scope{} = scope, loan_account_id) do
    RestructuringRequest
    |> scope_organisation(scope)
    |> where([r], r.loan_account_id == ^loan_account_id)
    |> order_by([r], desc: r.inserted_at)
    |> Repo.all()
  end

  def get_restructuring_request!(%Scope{} = scope, id) do
    RestructuringRequest
    |> scope_organisation(scope)
    |> Repo.get!(id)
  end

  @doc "Requests a term extension on `account`'s remaining schedule — decided later by a different, authorised staff member."
  def request_restructuring(%LoanAccount{} = account, attrs) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.put("organisation_id", account.organisation_id)
      |> Map.put("loan_account_id", account.id)

    %RestructuringRequest{}
    |> RestructuringRequest.changeset(attrs)
    |> Repo.insert()
  end

  def reject_restructuring(%RestructuringRequest{status: "pending"} = request, approver_id, notes) do
    request
    |> RestructuringRequest.decision_changeset(%{
      status: "rejected",
      decided_by_id: approver_id,
      decided_at: DateTime.utc_now() |> DateTime.truncate(:second),
      decision_notes: notes
    })
    |> Repo.update()
  end

  def reject_restructuring(%RestructuringRequest{}, _approver_id, _notes), do: {:error, :invalid_status}

  @doc """
  Approves a term-extension request: marks every remaining unpaid
  installment `"restructured"` (never deleted) and generates a fresh
  schedule for the true remaining principal (derived per-installment
  via the same interest-first convention `Payments`'s allocator
  already uses, not the full remaining scheduled amount, which would
  double-count old-plan interest) over the extended term, reusing
  `InterestCalculator.calculate/1`. Extending the term at the same
  rate on the same principal recognizes more total interest (a real
  economic effect of restructuring, not balance-neutral) — the
  difference is added to `outstanding_balance` and posted as a
  balanced ledger/GL entry, same "only post a real difference"
  convention already used for origination fees and penalties.
  """
  def approve_restructuring(%RestructuringRequest{status: "pending"} = request, approver_id) do
    with :ok <- check_not_requester(request.requested_by_id, approver_id) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      account = Repo.get!(LoanAccount, request.loan_account_id)

      remaining =
        RepaymentScheduleInstallment
        |> where([i], i.loan_account_id == ^account.id and i.status in ["upcoming", "overdue", "partially_paid"])
        |> order_by([i], asc: i.due_date)
        |> Repo.all()

      remaining_principal =
        remaining
        |> Enum.reduce(Decimal.new("0.00"), fn installment, acc ->
          paid_interest = decimal_min(installment.paid_amount, installment.scheduled_interest)
          paid_principal = Decimal.sub(installment.paid_amount, paid_interest)
          Decimal.add(acc, Decimal.sub(installment.scheduled_principal, paid_principal))
        end)

      old_remaining_total =
        Enum.reduce(remaining, Decimal.new("0.00"), fn i, acc ->
          Decimal.add(acc, Decimal.sub(i.scheduled_amount, i.paid_amount))
        end)

      new_term_months = length(remaining) + request.additional_term_months
      next_installment_number = (Repo.aggregate(from(i in RepaymentScheduleInstallment, where: i.loan_account_id == ^account.id), :max, :installment_number) || 0) + 1

      %{monthly_payment: monthly_payment} =
        InterestCalculator.calculate(%{amount: remaining_principal, interest_rate: account.interest_rate, term_months: new_term_months})

      new_installments = build_restructured_schedule(account, remaining_principal, monthly_payment, new_term_months, next_installment_number, now)
      new_remaining_total = Enum.reduce(new_installments, Decimal.new("0.00"), &Decimal.add(&2, &1.scheduled_amount))
      delta = Decimal.sub(new_remaining_total, old_remaining_total)

      Ecto.Multi.new()
      |> Ecto.Multi.update(:request, RestructuringRequest.decision_changeset(request, %{
        status: "approved", decided_by_id: approver_id, decided_at: now
      }))
      |> Ecto.Multi.run(:restructure_old, fn repo, _changes ->
        Enum.each(remaining, fn i -> i |> RepaymentScheduleInstallment.changeset(%{status: "restructured"}) |> repo.update!() end)
        {:ok, :restructured}
      end)
      |> Ecto.Multi.insert_all(:new_schedule, RepaymentScheduleInstallment, new_installments)
      |> Ecto.Multi.update(:account, LoanAccount.changeset(account, %{outstanding_balance: Decimal.add(account.outstanding_balance, delta)}))
      |> maybe_post_restructure_entry(delta, account, now)
      |> Repo.transaction()
      |> case do
        {:ok, %{request: request}} -> {:ok, request}
        {:error, _, reason, _} -> {:error, reason}
      end
    end
  end

  def approve_restructuring(%RestructuringRequest{}, _approver_id), do: {:error, :invalid_status}

  defp build_restructured_schedule(account, remaining_principal, monthly_payment, term_months, start_number, now) do
    base_date = Date.utc_today()
    monthly_rate = Decimal.div(account.interest_rate, Decimal.new("1200"))

    {installments, _} =
      Enum.map_reduce(0..(term_months - 1), remaining_principal, fn n, remaining ->
        installment_number = start_number + n
        interest_due = remaining |> Decimal.mult(monthly_rate) |> Decimal.round(2)

        principal_due =
          if n == term_months - 1 do
            remaining
          else
            monthly_payment |> Decimal.sub(interest_due) |> Decimal.round(2)
          end

        row = %{
          id: Ecto.UUID.generate(),
          organisation_id: account.organisation_id,
          loan_account_id: account.id,
          installment_number: installment_number,
          due_date: Timex.shift(base_date, months: n + 1),
          scheduled_amount: Decimal.add(principal_due, interest_due),
          scheduled_principal: principal_due,
          scheduled_interest: interest_due,
          paid_amount: Decimal.new("0.00"),
          status: "upcoming",
          inserted_at: now |> DateTime.to_naive(),
          updated_at: now |> DateTime.to_naive()
        }

        {row, Decimal.sub(remaining, principal_due)}
      end)

    installments
  end

  defp maybe_post_restructure_entry(multi, delta, account, now) do
    if Decimal.compare(delta, Decimal.new("0")) == :gt do
      multi
      |> Ecto.Multi.insert(:restructure_entry, AccountingEntry.changeset(%AccountingEntry{}, %{
        organisation_id: account.organisation_id,
        loan_account_id: account.id,
        entry_type: "fee",
        amount: delta,
        running_balance: Decimal.add(account.outstanding_balance, delta),
        source_type: "loan_account",
        source_id: account.id,
        description: "Interest recognized on loan restructuring",
        occurred_at: now
      }))
      |> MiwayCreditCore.Accounting.GeneralLedger.post_journal_entry(:restructure_gl, %{
        organisation_id: account.organisation_id,
        description: "Interest recognized on loan restructuring",
        source_type: "loan_account",
        source_id: account.id,
        occurred_at: now,
        lines: [%{account_code: "1100", debit: delta}, %{account_code: "4000", credit: delta}]
      })
    else
      multi
    end
  end

  def list_write_off_requests_for_account(%Scope{} = scope, loan_account_id) do
    WriteOffRequest
    |> scope_organisation(scope)
    |> where([r], r.loan_account_id == ^loan_account_id)
    |> order_by([r], desc: r.inserted_at)
    |> Repo.all()
  end

  def get_write_off_request!(%Scope{} = scope, id) do
    WriteOffRequest
    |> scope_organisation(scope)
    |> Repo.get!(id)
  end

  @doc "Requests a write-off of account's current outstanding_balance — decided later by a different, authorised staff member."
  def request_write_off(%LoanAccount{} = account, attrs) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.put("organisation_id", account.organisation_id)
      |> Map.put("loan_account_id", account.id)
      |> Map.put("requested_amount", account.outstanding_balance)

    %WriteOffRequest{}
    |> WriteOffRequest.changeset(attrs)
    |> Repo.insert()
  end

  def reject_write_off(%WriteOffRequest{status: "pending"} = request, approver_id, notes) do
    request
    |> WriteOffRequest.decision_changeset(%{
      status: "rejected",
      decided_by_id: approver_id,
      decided_at: DateTime.utc_now() |> DateTime.truncate(:second),
      decision_notes: notes
    })
    |> Repo.update()
  end

  def reject_write_off(%WriteOffRequest{}, _approver_id, _notes), do: {:error, :invalid_status}

  @doc "Approves a write-off request — calls through to the existing Lending.write_off_account/2 rather than duplicating it."
  def approve_write_off(%WriteOffRequest{status: "pending"} = request, approver_id) do
    with :ok <- check_not_requester(request.requested_by_id, approver_id) do
      account = Repo.get!(LoanAccount, request.loan_account_id)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Ecto.Multi.new()
      |> Ecto.Multi.update(:request, WriteOffRequest.decision_changeset(request, %{
        status: "approved", decided_by_id: approver_id, decided_at: now
      }))
      |> Ecto.Multi.run(:write_off, fn _repo, _changes -> Lending.write_off_account(account, approver_id) end)
      |> Repo.transaction()
      |> case do
        {:ok, %{request: request}} -> {:ok, request}
        {:error, _, reason, _} -> {:error, reason}
      end
    end
  end

  def approve_write_off(%WriteOffRequest{}, _approver_id), do: {:error, :invalid_status}

  defp check_not_requester(requested_by_id, approver_id) do
    if requested_by_id == approver_id, do: {:error, :maker_checker_violation}, else: :ok
  end

  defp decimal_min(a, b), do: if(Decimal.compare(a, b) == :gt, do: b, else: a)

  defp stringify_keys(attrs) do
    Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
  end

  defp scope_organisation(query, %Scope{organisation_id: :all}), do: query
  defp scope_organisation(query, %Scope{organisation_id: organisation_id}) do
    where(query, organisation_id: ^organisation_id)
  end
end
