defmodule LoanSystemWeb.ClientLoanController do
  use LoanSystemWeb, :controller

  alias LoanSystem.{Loans, Clients}

  def index(conn, _params) do
    client = client_for(conn)
    loans = Loans.get_loans_for_client(client.id)
    render(conn, :index, loans: loans)
  end

  def show(conn, %{"id" => id}) do
    client = client_for(conn)
    loan = Loans.get_loan!(id) |> LoanSystem.Repo.preload(:payments)

    # Authorization: ensure this loan belongs to the current client
    if loan.client_id != client.id do
      conn
      |> put_flash(:error, "You are not authorized to view this loan.")
      |> redirect(to: ~p"/client/loans")
      |> halt()
    else
      interest = Loans.compound_interest_details(loan)
      render(conn, :show, loan: loan, interest: interest)
    end
  end

  defp client_for(conn) do
    user = conn.assigns.current_user
    Clients.get_client_by_email(user.email) ||
      raise "No client record found for user #{user.email}"
  end
end
