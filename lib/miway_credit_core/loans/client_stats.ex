defmodule MiwayCreditCore.Loans.ClientStats do
  @moduledoc false

  # Recalculates a client's denormalized total_loans/current_balance.
  # total_loans counts every application ever submitted (matches the
  # original "every request counts" semantic); current_balance sums
  # outstanding_balance across that client's active loan accounts only —
  # a pending application has no real balance yet, unlike the old model
  # where a pending loan's remaining_balance (== its full requested
  # amount) was incorrectly included.

  import Ecto.Query
  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.Clients.Client
  alias MiwayCreditCore.Loans.{LoanApplication, LoanAccount}

  def recalculate(repo \\ Repo, client_id) do
    balance =
      from(a in LoanAccount,
        where: a.client_id == ^client_id and a.status == "active",
        select: sum(a.outstanding_balance)
      )
      |> repo.one()
      |> then(fn
        nil -> Decimal.new("0.00")
        val -> val
      end)

    count =
      from(la in LoanApplication, where: la.client_id == ^client_id, select: count(la.id))
      |> repo.one()

    from(c in Client, where: c.id == ^client_id)
    |> repo.update_all(set: [current_balance: balance, total_loans: count])

    {:ok, :updated}
  end
end
