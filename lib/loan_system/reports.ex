defmodule LoanSystem.Reports do
  @moduledoc """
  Portfolio-level reporting for the admin Reports page — aggregate
  numbers, the overdue/upcoming work queues, and a CSV export. Built on
  top of the existing Loans/Clients contexts rather than duplicating
  their queries.
  """

  import Ecto.Query
  alias LoanSystem.{Repo, Loans, Clients}
  alias LoanSystem.Loans.{Payment, Loan}

  @doc "Portfolio-wide numbers for the Reports overview."
  def portfolio_summary do
    %{
      total_clients: Clients.count_clients(),
      total_loans: Loans.count_loans(),
      active_loans: Loans.count_active_loans(),
      outstanding_balance: Loans.total_outstanding_balance(),
      overdue_count: Loans.count_overdue_payments(),
      overdue_amount: Loans.total_overdue_amount()
    }
  end

  @doc "Every overdue installment, oldest due_date (most urgent) first, with loan + client preloaded."
  def overdue_payments do
    Payment
    |> where([p], p.status == "overdue")
    |> order_by([p], asc: p.due_date)
    |> preload(loan: :client)
    |> Repo.all()
  end

  @doc "Pending installments due within the next `days` days (default 7), portfolio-wide."
  def payments_due_soon(days \\ 7) do
    today = Date.utc_today()
    cutoff = Date.add(today, days)

    Payment
    |> where([p], p.status == "pending" and p.due_date >= ^today and p.due_date <= ^cutoff)
    |> order_by([p], asc: p.due_date)
    |> preload(loan: :client)
    |> Repo.all()
  end

  @doc """
  A CSV export of every loan — id, client, status, risk level, amount,
  remaining balance, approved date. Hand-built rather than pulling in a
  CSV dependency for one export.
  """
  def loans_csv do
    header = ~w(loan_id client_name status risk_level amount remaining_balance approved_at)

    rows =
      Loan
      |> preload(:client)
      |> order_by([l], desc: l.inserted_at)
      |> Repo.all()
      |> Enum.map(fn loan ->
        [
          loan.id,
          loan.client.name,
          loan.status,
          loan.risk_level,
          Decimal.to_string(loan.amount),
          Decimal.to_string(loan.remaining_balance),
          (loan.approved_at && NaiveDateTime.to_date(loan.approved_at) |> Date.to_iso8601()) || ""
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
