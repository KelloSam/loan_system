defmodule MiwayCreditCoreWeb.AdminDashboardController do
  use MiwayCreditCoreWeb, :controller

  alias MiwayCreditCore.{Applications, AuditLogs, Reports}

  def index(conn, _params) do
    scope = conn.assigns.current_scope

    stats = Reports.portfolio_summary(scope)
    recent_applications = Applications.list_applications(scope, per_page: 6)
    recent_events = AuditLogs.list_recent(scope, 5)
    ledger_health = Reports.ledger_health(scope)

    render(conn, :index,
      stats: stats,
      recent_applications: recent_applications,
      recent_events: recent_events,
      ledger_health: ledger_health
    )
  end
end
