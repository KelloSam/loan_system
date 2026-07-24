defmodule MiwayCreditCoreWeb.ClientLoanController do
  use MiwayCreditCoreWeb, :controller

  alias MiwayCreditCore.{Loans, Clients}

  def index(conn, _params) do
    client = client_for(conn)
    applications = Loans.get_applications_for_client(client.id)
    render(conn, :index, applications: applications)
  end

  def show(conn, %{"id" => id}) do
    client = client_for(conn)
    application = Loans.get_application!(id)

    # Authorization: ensure this application belongs to the current client
    if application.client_id != client.id do
      conn
      |> put_flash(:error, "You are not authorized to view this loan.")
      |> redirect(to: ~p"/client/loans")
      |> halt()
    else
      {account, interest, installments} =
        case application.loan_account do
          nil -> {nil, nil, []}
          account ->
            {account, Loans.compound_interest_details(account),
             Loans.list_installments_for_account(account.id)}
        end

      render(conn, :show, application: application, account: account, interest: interest,
        installments: installments)
    end
  end

  defp client_for(conn) do
    user = conn.assigns.current_user
    Clients.get_client_by_email(user.email) ||
      raise "No client record found for user #{user.email}"
  end
end
