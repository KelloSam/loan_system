defmodule MiwayCreditCoreWeb.CustomerDashboardController do
  use MiwayCreditCoreWeb, :controller

  alias MiwayCreditCore.{Customers, Loans}

  def index(conn, _params) do
    user = conn.assigns.current_user
    customer = Customers.get_customer_by_email(user.email)

    {applications, next_payment_date, next_payment_amount} =
      if customer do
        apps = Loans.get_applications_for_customer(customer.id)

        case Loans.get_upcoming_installments(customer.id) |> List.first() do
          %{due_date: date, scheduled_amount: amount, paid_amount: paid} ->
            {apps, date, Decimal.sub(amount, paid)}

          nil ->
            {apps, nil, nil}
        end
      else
        {[], nil, nil}
      end

    render(conn, :index,
      customer: customer,
      applications: applications,
      next_payment_date: next_payment_date,
      next_payment_amount: next_payment_amount
    )
  end
end
