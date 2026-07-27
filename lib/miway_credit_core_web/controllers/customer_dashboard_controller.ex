defmodule MiwayCreditCoreWeb.CustomerDashboardController do
  use MiwayCreditCoreWeb, :controller

  alias MiwayCreditCore.Loans

  def index(conn, _params) do
    customer = conn.assigns.current_customer
    applications = Loans.get_applications_for_customer(customer.id)

    {next_payment_date, next_payment_amount} =
      case Loans.get_upcoming_installments(customer.id) |> List.first() do
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
