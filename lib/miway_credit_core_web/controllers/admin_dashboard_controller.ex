defmodule MiwayCreditCoreWeb.AdminDashboardController do
  use MiwayCreditCoreWeb, :controller

  alias MiwayCreditCore.{Clients, Loans, AuditLogs}

  def index(conn, _params) do
    stats = %{
      total_clients: Clients.count_clients(),
      total_loans: Loans.count_applications(),
      active_loans: Loans.count_active_accounts(),
      outstanding_balance: Loans.total_outstanding_balance()
    }

    recent_applications = Loans.list_applications(per_page: 6)
    recent_events = AuditLogs.list_recent(5)

    render(conn, :index, stats: stats, recent_applications: recent_applications, recent_events: recent_events)
  end
end
