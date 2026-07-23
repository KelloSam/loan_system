defmodule MiwayCreditCoreWeb.ClientDashboardController do
  use MiwayCreditCoreWeb, :controller

  alias MiwayCreditCore.{Clients, Loans}

  def index(conn, _params) do
    user = conn.assigns.current_user
    client = Clients.get_client_by_email(user.email)

    {loans, next_payment_date, next_payment_amount} =
      if client do
        ls = Loans.get_loans_for_client(client.id)

        # Prefer a pending Payment record; fall back to the loan's next_payment_date field
        case Loans.get_upcoming_payments(client.id) |> List.first() do
          %{payment_date: date, amount: amount} ->
            {ls, date, amount}

          nil ->
            # Find the earliest next_payment_date across active loans
            active = Enum.filter(ls, &(&1.status in ["approved", "pending"] and &1.next_payment_date))
            case Enum.min_by(active, & &1.next_payment_date, fn -> nil end) do
              nil  -> {ls, nil, nil}
              loan -> {ls, loan.next_payment_date, nil}
            end
        end
      else
        {[], nil, nil}
      end

    render(conn, :index,
      client: client,
      loans: loans,
      next_payment_date: next_payment_date,
      next_payment_amount: next_payment_amount
    )
  end
end
