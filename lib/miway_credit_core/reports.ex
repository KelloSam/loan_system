defmodule MiwayCreditCore.Reports do
  @moduledoc """
  Portfolio-level reporting for the admin Reports page — aggregate
  numbers, the overdue/upcoming work queues, and a CSV export. Built on
  top of the existing Applications/Lending/Customers contexts rather
  than duplicating their queries.
  """

  import Ecto.Query
  alias MiwayCreditCore.{Repo, Applications, Lending, Customers, Collections, Accounting}
  alias MiwayCreditCore.Applications.LoanApplication
  alias MiwayCreditCore.Lending.RepaymentScheduleInstallment
  alias MiwayCreditCore.Accounts.Scope

  @doc "Portfolio-wide numbers for the Reports overview, scoped to the caller's organisation."
  def portfolio_summary(%Scope{} = scope) do
    outstanding_balance = Lending.total_outstanding_balance(scope)
    overdue_amount = Lending.total_overdue_amount(scope)

    %{
      total_customers: Customers.count_customers(scope),
      total_loans: Applications.count_applications(scope),
      active_loans: Lending.count_active_accounts(scope),
      outstanding_balance: outstanding_balance,
      overdue_count: Lending.count_overdue_installments(scope),
      overdue_amount: overdue_amount,
      par_percent: par_percent(overdue_amount, outstanding_balance),
      open_collection_cases: Collections.count_open_cases(scope)
    }
  end

  @doc """
  Portfolio at risk — the standard lending KPI, overdue amount as a
  percentage of outstanding balance. Zero-safe: an empty portfolio has
  nothing at risk, not a division error.
  """
  def par_percent(overdue_amount, outstanding_balance) do
    if Decimal.equal?(outstanding_balance, Decimal.new("0")) do
      Decimal.new("0")
    else
      overdue_amount
      |> Decimal.div(outstanding_balance)
      |> Decimal.mult(Decimal.new("100"))
      |> Decimal.round(1)
    end
  end

  @doc "Trial balance (balanced?/total_debits/total_credits) for the caller's organisation — Step 14's ledger, surfaced in reporting."
  defdelegate ledger_health(scope), to: Accounting, as: :trial_balance

  @doc "Per-cash-account-type balances for the caller's organisation — Step 14's reconciliation baseline, surfaced in reporting."
  defdelegate cash_position(scope), to: Accounting

  @doc "Every overdue installment, oldest due_date (most urgent) first, with account + customer preloaded."
  def overdue_payments(%Scope{} = scope) do
    RepaymentScheduleInstallment
    |> scope_organisation(scope)
    |> where([i], i.status == "overdue")
    |> order_by([i], asc: i.due_date)
    |> preload(loan_account: [:customer, :loan_application])
    |> Repo.all()
  end

  @doc "Installments due within the next `days` days (default 7), scoped to the caller's organisation."
  def payments_due_soon(%Scope{} = scope, days \\ 7) do
    today = Date.utc_today()
    cutoff = Date.add(today, days)

    RepaymentScheduleInstallment
    |> scope_organisation(scope)
    |> where(
      [i],
      i.status in ["upcoming", "partially_paid"] and i.due_date >= ^today and
        i.due_date <= ^cutoff
    )
    |> order_by([i], asc: i.due_date)
    |> preload(loan_account: [:customer, :loan_application])
    |> Repo.all()
  end

  @doc """
  A CSV export of every loan application — id, customer, status, risk
  level, requested amount, granted amount, outstanding balance,
  decided date. Granted amount / outstanding balance are blank for
  applications that never reached an approved account. Hand-built
  rather than pulling in a CSV dependency for one export.
  """
  def loans_csv(%Scope{} = scope) do
    header =
      ~w(application_id customer_name status risk_level requested_amount granted_amount outstanding_balance decided_at)

    rows =
      LoanApplication
      |> scope_organisation(scope)
      |> preload([:customer, :loan_account])
      |> order_by([a], desc: a.inserted_at)
      |> Repo.all()
      |> Enum.map(fn application ->
        [
          application.id,
          application.customer.name,
          application.status,
          application.risk_level,
          Decimal.to_string(application.requested_amount),
          (application.loan_account &&
             Decimal.to_string(application.loan_account.principal_amount)) || "",
          (application.loan_account &&
             Decimal.to_string(application.loan_account.outstanding_balance)) || "",
          (application.decided_at && DateTime.to_date(application.decided_at) |> Date.to_iso8601()) ||
            ""
        ]
      end)

    [header | rows]
    |> Enum.map(&csv_row/1)
    |> Enum.join()
  end

  defp scope_organisation(query, %Scope{organisation_id: :all}), do: query

  defp scope_organisation(query, %Scope{organisation_id: organisation_id}) do
    where(query, organisation_id: ^organisation_id)
  end

  defp csv_row(fields) do
    fields
    |> Enum.map(&csv_escape/1)
    |> Enum.join(",")
    |> Kernel.<>("\r\n")
  end

  defp csv_escape(field) do
    field = to_string(field)

    if String.contains?(field, [",", "\"", "\n"]) do
      "\"" <> String.replace(field, "\"", "\"\"") <> "\""
    else
      field
    end
  end
end
