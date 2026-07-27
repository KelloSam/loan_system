defmodule MiwayCreditCoreWeb.CustomerDashboardController do
  use MiwayCreditCoreWeb, :controller

  alias MiwayCreditCore.{Applications, Lending}

  def index(conn, _params) do
    scope = conn.assigns.current_scope
    customer = conn.assigns.current_customer
    applications = Applications.get_applications_for_customer(scope, customer.id)

    {next_payment_date, next_payment_amount} =
      case Lending.get_upcoming_installments(scope, customer.id) |> List.first() do
        %{due_date: date, scheduled_amount: amount, paid_amount: paid} ->
          {date, Decimal.sub(amount, paid)}

        nil ->
          {nil, nil}
      end

    render(conn, :index,
      customer: customer,
      applications: applications,
      next_payment_date: next_payment_date,
      next_payment_amount: next_payment_amount
    )
  end
end
