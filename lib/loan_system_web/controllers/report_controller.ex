defmodule LoanSystemWeb.ReportController do
  use LoanSystemWeb, :controller

  alias LoanSystem.Reports

  def index(conn, _params) do
    render(conn, :index,
      summary: Reports.portfolio_summary(),
      overdue_payments: Reports.overdue_payments(),
      payments_due_soon: Reports.payments_due_soon()
    )
  end

  def export_csv(conn, _params) do
    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="loans.csv"))
    |> send_resp(200, Reports.loans_csv())
  end
end
