defmodule MiwayCreditCore.Lending.Schedule do
  @moduledoc """
  Read access to the repayment plan, plus the arrears sweep. Rows here
  are never touched by money-received logic directly — only by
  `mark_overdue_installments/0` (time-based) and payment allocation
  (money-based, see `MiwayCreditCore.Payments`).
  """

  import Ecto.Query
  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.Lending.RepaymentScheduleInstallment
  alias MiwayCreditCore.Accounts.Scope

  def list_installments_for_account(%Scope{} = scope, loan_account_id) do
    RepaymentScheduleInstallment
    |> scope_organisation(scope)
    |> where([i], i.loan_account_id == ^loan_account_id)
    |> order_by([i], asc: i.installment_number)
    |> Repo.all()
  end

  def get_installment!(%Scope{} = scope, id) do
    RepaymentScheduleInstallment
    |> scope_organisation(scope)
    |> Repo.get!(id)
  end

  @doc "Earliest unpaid installment due for a customer, ordered by due_date, loan_account preloaded."
  def get_upcoming_installments(%Scope{} = scope, customer_id) do
    RepaymentScheduleInstallment
    |> scope_organisation(scope)
    |> join(:inner, [i], a in assoc(i, :loan_account))
    |> where([i, a], a.customer_id == ^customer_id)
    |> where([i], i.status in ["upcoming", "overdue", "partially_paid"])
    |> order_by([i], asc: i.due_date)
    |> preload(:loan_account)
    |> Repo.all()
  end

  @doc """
  Flips every unpaid installment whose due_date has passed to
  "overdue", across every organisation — this is a system-wide batch
  job (called periodically by MiwayCreditCore.ArrearsScheduler), not a
  request handler, so it deliberately has no scope. Returns the number
  of rows flipped.
  """
  def mark_overdue_installments do
    today = Date.utc_today()

    {count, _} =
      from(i in RepaymentScheduleInstallment,
        where: i.status in ["upcoming", "partially_paid"] and i.due_date < ^today
      )
      |> Repo.update_all(set: [status: "overdue"])

    count
  end

  @doc "Count of overdue installments, optionally scoped to one customer."
  def count_overdue_installments(%Scope{} = scope, customer_id \\ nil) do
    RepaymentScheduleInstallment
    |> scope_organisation(scope)
    |> maybe_join_customer(customer_id)
    |> where([i], i.status == "overdue")
    |> Repo.aggregate(:count)
  end

  @doc "Total value of all overdue installments, optionally scoped to one customer."
  def total_overdue_amount(%Scope{} = scope, customer_id \\ nil) do
    RepaymentScheduleInstallment
    |> scope_organisation(scope)
    |> maybe_join_customer(customer_id)
    |> where([i], i.status == "overdue")
    |> select([i], coalesce(sum(i.scheduled_amount - i.paid_amount), ^Decimal.new("0.00")))
    |> Repo.one()
  end

  @doc "Overdue installments, oldest due_date first, loan_account + customer preloaded."
  def overdue_installments(%Scope{} = scope) do
    RepaymentScheduleInstallment
    |> scope_organisation(scope)
    |> where([i], i.status == "overdue")
    |> order_by([i], asc: i.due_date)
    |> preload(loan_account: :customer)
    |> Repo.all()
  end

  @doc "Installments due within the next `days` days (default 7), scoped to the caller's organisation."
  def installments_due_soon(%Scope{} = scope, days \\ 7) do
    today = Date.utc_today()
    cutoff = Date.add(today, days)

    RepaymentScheduleInstallment
    |> scope_organisation(scope)
    |> where([i], i.status in ["upcoming", "partially_paid"] and i.due_date >= ^today and i.due_date <= ^cutoff)
    |> order_by([i], asc: i.due_date)
    |> preload(loan_account: :customer)
    |> Repo.all()
  end

  defp scope_organisation(query, %Scope{organisation_id: :all}), do: query
  defp scope_organisation(query, %Scope{organisation_id: organisation_id}) do
    where(query, organisation_id: ^organisation_id)
  end

  defp maybe_join_customer(query, nil), do: query

  defp maybe_join_customer(query, customer_id) do
    query
    |> join(:inner, [i], a in assoc(i, :loan_account))
    |> where([i, a], a.customer_id == ^customer_id)
  end
end
