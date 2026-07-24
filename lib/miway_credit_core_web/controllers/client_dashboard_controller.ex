defmodule MiwayCreditCoreWeb.ClientDashboardController do
  use MiwayCreditCoreWeb, :controller

  alias MiwayCreditCore.{Clients, Loans}

  def index(conn, _params) do
    user = conn.assigns.current_user
    client = Clients.get_client_by_email(user.email)

    {applications, next_payment_date, next_payment_amount} =
      if client do
        apps = Loans.get_applications_for_client(client.id)

        case Loans.get_upcoming_installments(client.id) |> List.first() do
          %{due_date: date, scheduled_amount: amount, paid_amount: paid} ->
            {apps, date, Decimal.sub(amount, paid)}

          nil ->
            {apps, nil, nil}
        end
      else
        {[], nil, nil}
      end

    render(conn, :index,
      client: client,
      applications: applications,
      next_payment_date: next_payment_date,
      next_payment_amount: next_payment_amount
    )
  end
end
