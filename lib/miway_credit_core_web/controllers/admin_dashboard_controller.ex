defmodule MiwayCreditCoreWeb.AdminDashboardController do
  use MiwayCreditCoreWeb, :controller

  alias MiwayCreditCore.{Customers, Applications, Lending, AuditLogs}

  def index(conn, _params) do
    scope = conn.assigns.current_scope

    stats = %{
      total_customers: Customers.count_customers(scope),
      total_loans: Applications.count_applications(scope),
      active_loans: Lending.count_active_accounts(scope),
      outstanding_balance: Lending.total_outstanding_balance(scope)
    }

    recent_applications = Applications.list_applications(scope, per_page: 6)
    recent_events = AuditLogs.list_recent(5)

    render(conn, :index, stats: stats, recent_applications: recent_applications, recent_events: recent_events)
  end
end
