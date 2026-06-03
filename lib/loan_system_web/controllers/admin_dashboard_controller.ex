defmodule LoanSystemWeb.AdminDashboardController do
  use LoanSystemWeb, :controller

  alias LoanSystem.{Clients, Loans}

  def index(conn, _params) do
    stats = %{
      total_clients: Clients.count_clients(),
      total_loans: Loans.count_loans(),
      active_loans: Loans.count_active_loans(),
      outstanding_balance: Loans.total_outstanding_balance()
    }

    recent_loans = Loans.list_loans(per_page: 6)

    render(conn, :index, stats: stats, recent_loans: recent_loans)
  end
end
