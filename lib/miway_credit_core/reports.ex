defmodule MiwayCreditCore.Reports do
  @moduledoc """
  Portfolio-level reporting for the admin Reports page — aggregate
  numbers, the overdue/upcoming work queues, and a CSV export. Built on
  top of the existing Loans/Clients contexts rather than duplicating
  their queries.
  """

  import Ecto.Query
  alias MiwayCreditCore.{Repo, Loans, Clients}
  alias MiwayCreditCore.Loans.{RepaymentScheduleInstallment, LoanApplication}

  @doc "Portfolio-wide numbers for the Reports overview."
  def portfolio_summary do
    %{
      total_clients: Clients.count_clients(),
      total_loans: Loans.count_applications(),
      active_loans: Loans.count_active_accounts(),
      outstanding_balance: Loans.total_outstanding_balance(),
      overdue_count: Loans.count_overdue_installments(),
      overdue_amount: Loans.total_overdue_amount()
    }
  end

  @doc "Every overdue installment, oldest due_date (most urgent) first, with account + client preloaded."
  def overdue_payments do
    RepaymentScheduleInstallment
    |> where([i], i.status == "overdue")
    |> order_by([i], asc: i.due_date)
    |> preload(loan_account: [:client, :loan_application])
    |> Repo.all()
  end

  @doc "Installments due within the next `days` days (default 7), portfolio-wide."
  def payments_due_soon(days \\ 7) do
    today = Date.utc_today()
    cutoff = Date.add(today, days)

    RepaymentScheduleInstallment
    |> where([i], i.status in ["upcoming", "partially_paid"] and i.due_date >= ^today and i.due_date <= ^cutoff)
    |> order_by([i], asc: i.due_date)
    |> preload(loan_account: [:client, :loan_application])
    |> Repo.all()
  end

  @doc """
  A CSV export of every loan application — id, client, status, risk
  level, requested amount, granted amount, outstanding balance,
  decided date. Granted amount / outstanding balance are blank for
  applications that never reached an approved account. Hand-built
  rather than pulling in a CSV dependency for one export.
  """
  def loans_csv do
    header = ~w(application_id client_name status risk_level requested_amount granted_amount outstanding_balance decided_at)

    rows =
      LoanApplication
      |> preload([:client, :loan_account])
      |> order_by([a], desc: a.inserted_at)
      |> Repo.all()
      |> Enum.map(fn application ->
        [
          application.id,
          application.client.name,
          application.status,
          application.risk_level,
          Decimal.to_string(application.requested_amount),
          (application.loan_account && Decimal.to_string(application.loan_account.principal_amount)) || "",
          (application.loan_account && Decimal.to_string(application.loan_account.outstanding_balance)) || "",
          (application.decided_at && DateTime.to_date(application.decided_at) |> Date.to_iso8601()) || ""
        ]
      end)

    [header | rows]
    |> Enum.map(&csv_row/1)
    |> Enum.join()
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
