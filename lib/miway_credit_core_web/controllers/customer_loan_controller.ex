defmodule MiwayCreditCoreWeb.CustomerLoanController do
  use MiwayCreditCoreWeb, :controller

  alias MiwayCreditCore.{Loans, Customers}

  def index(conn, _params) do
    customer = customer_for(conn)
    applications = Loans.get_applications_for_customer(customer.id)
    render(conn, :index, applications: applications)
  end

  def show(conn, %{"id" => id}) do
    customer = customer_for(conn)
    application = Loans.get_application!(id)

    # Authorization: ensure this application belongs to the current customer
    if application.customer_id != customer.id do
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

  defp customer_for(conn) do
    user = conn.assigns.current_user
    Customers.get_customer_by_email(user.email) ||
      raise "No customer record found for user #{user.email}"
  end
end
