defmodule MiwayCreditCoreWeb.CustomerLoanController do
  use MiwayCreditCoreWeb, :controller

  alias MiwayCreditCore.Loans

  def index(conn, _params) do
    customer = conn.assigns.current_customer
    applications = Loans.get_applications_for_customer(customer.id)
    render(conn, :index, applications: applications)
  end

  def show(conn, %{"id" => id}) do
    customer = conn.assigns.current_customer
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
end
