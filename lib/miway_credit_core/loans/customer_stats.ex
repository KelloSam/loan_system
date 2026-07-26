defmodule MiwayCreditCore.Loans.CustomerStats do
  @moduledoc false

  # Recalculates a customer's denormalized total_loans/current_balance.
  # total_loans counts every application ever submitted (matches the
  # original "every request counts" semantic); current_balance sums
  # outstanding_balance across that customer's active loan accounts only —
  # a pending application has no real balance yet, unlike the old model
  # where a pending loan's remaining_balance (== its full requested
  # amount) was incorrectly included.

  import Ecto.Query
  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.Customers.Customer
  alias MiwayCreditCore.Loans.LoanApplication
  alias MiwayCreditCore.Lending.LoanAccount

  def recalculate(repo \\ Repo, customer_id) do
    balance =
      from(a in LoanAccount,
        where: a.customer_id == ^customer_id and a.status == "active",
        select: sum(a.outstanding_balance)
      )
      |> repo.one()
      |> then(fn
        nil -> Decimal.new("0.00")
        val -> val
      end)

    count =
      from(la in LoanApplication, where: la.customer_id == ^customer_id, select: count(la.id))
      |> repo.one()

    from(c in Customer, where: c.id == ^customer_id)
    |> repo.update_all(set: [current_balance: balance, total_loans: count])

    {:ok, :updated}
  end
end
