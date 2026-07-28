defmodule MiwayCreditCoreWeb.ReportController do
  use MiwayCreditCoreWeb, :controller

  alias MiwayCreditCore.Reports
  alias MiwayCreditCoreWeb.Plugs.RequirePermissionPlug

  plug RequirePermissionPlug, "reports.view" when action in [:index, :export_csv]

  def index(conn, _params) do
    scope = conn.assigns.current_scope

    render(conn, :index,
      summary: Reports.portfolio_summary(scope),
      overdue_payments: Reports.overdue_payments(scope),
      payments_due_soon: Reports.payments_due_soon(scope)
    )
  end

  def export_csv(conn, _params) do
    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="loans.csv"))
    |> send_resp(200, Reports.loans_csv(conn.assigns.current_scope))
  end
end
