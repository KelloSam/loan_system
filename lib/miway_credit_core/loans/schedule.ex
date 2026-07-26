defmodule MiwayCreditCore.Loans.Schedule do
  @moduledoc """
  Read access to the repayment plan, plus the arrears sweep. Rows here
  are never touched by money-received logic directly — only by
  `mark_overdue_installments/0` (time-based) and payment allocation
  (money-based, see `MiwayCreditCore.Loans.Payments`).
  """

  import Ecto.Query
  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.Loans.RepaymentScheduleInstallment

  def list_installments_for_account(loan_account_id) do
    RepaymentScheduleInstallment
    |> where([i], i.loan_account_id == ^loan_account_id)
    |> order_by([i], asc: i.installment_number)
    |> Repo.all()
  end

  def get_installment!(id), do: Repo.get!(RepaymentScheduleInstallment, id)

  @doc "Earliest unpaid installment due for a customer, ordered by due_date, loan_account preloaded."
  def get_upcoming_installments(customer_id) do
    RepaymentScheduleInstallment
    |> join(:inner, [i], a in assoc(i, :loan_account))
    |> where([i, a], a.customer_id == ^customer_id)
    |> where([i], i.status in ["upcoming", "overdue", "partially_paid"])
    |> order_by([i], asc: i.due_date)
    |> preload(:loan_account)
    |> Repo.all()
  end

  @doc """
  Flips every unpaid installment whose due_date has passed to
  "overdue". Called periodically by MiwayCreditCore.ArrearsScheduler;
  also safe to call directly. Returns the number of rows flipped.
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
  def count_overdue_installments(customer_id \\ nil) do
    RepaymentScheduleInstallment
    |> maybe_join_customer(customer_id)
    |> where([i], i.status == "overdue")
    |> Repo.aggregate(:count)
  end

  @doc "Total value of all overdue installments, optionally scoped to one customer."
  def total_overdue_amount(customer_id \\ nil) do
    RepaymentScheduleInstallment
    |> maybe_join_customer(customer_id)
    |> where([i], i.status == "overdue")
    |> select([i], coalesce(sum(i.scheduled_amount - i.paid_amount), ^Decimal.new("0.00")))
    |> Repo.one()
  end

  @doc "Overdue installments, oldest due_date first, loan_account + customer preloaded."
  def overdue_installments do
    RepaymentScheduleInstallment
    |> where([i], i.status == "overdue")
    |> order_by([i], asc: i.due_date)
    |> preload(loan_account: :customer)
    |> Repo.all()
  end

  @doc "Installments due within the next `days` days (default 7), portfolio-wide."
  def installments_due_soon(days \\ 7) do
    today = Date.utc_today()
    cutoff = Date.add(today, days)

    RepaymentScheduleInstallment
    |> where([i], i.status in ["upcoming", "partially_paid"] and i.due_date >= ^today and i.due_date <= ^cutoff)
    |> order_by([i], asc: i.due_date)
    |> preload(loan_account: :customer)
    |> Repo.all()
  end

  defp maybe_join_customer(query, nil), do: query

  defp maybe_join_customer(query, customer_id) do
    query
    |> join(:inner, [i], a in assoc(i, :loan_account))
    |> where([i, a], a.customer_id == ^customer_id)
  end
end
