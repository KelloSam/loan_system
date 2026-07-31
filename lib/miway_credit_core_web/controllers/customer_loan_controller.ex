defmodule MiwayCreditCoreWeb.CustomerLoanController do
  use MiwayCreditCoreWeb, :controller

  alias MiwayCreditCore.{Applications, Lending}

  def index(conn, _params) do
    customer = conn.assigns.current_customer

    applications =
      Applications.get_applications_for_customer(conn.assigns.current_scope, customer.id)

    render(conn, :index, applications: applications)
  end

  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    customer = conn.assigns.current_customer
    application = Applications.get_application!(scope, id)

    # Authorization: ensure this application belongs to the current customer
    if application.customer_id != customer.id do
      conn
      |> put_flash(:error, "You are not authorized to view this loan.")
      |> redirect(to: ~p"/client/loans")
      |> halt()
    else
      {account, interest, installments} =
        case application.loan_account do
          nil ->
            {nil, nil, []}

          account ->
            {account, Lending.compound_interest_details(account),
             Lending.list_installments_for_account(scope, account.id)}
        end

      render(conn, :show,
        application: application,
        account: account,
        interest: interest,
        installments: installments
      )
    end
  end
end
