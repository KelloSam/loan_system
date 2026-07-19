defmodule LoanSystem.Loans do
  import Ecto.Query
  alias LoanSystem.Repo
  alias LoanSystem.Loans.{Loan, Payment, Collateral, InterestCalculator}
  alias LoanSystem.Clients.Client
  alias LoanSystem.FraudDetector

  # ---------------------------------------------------------------------------
  # Loan queries
  # ---------------------------------------------------------------------------

  @doc """
  Returns a paginated list of loans with client preloaded.
  Accepts `page:` and `per_page:` opts (defaults: 1, 50).
  """
  def list_loans(opts \\ []) do
    page     = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 50)
    offset   = (page - 1) * per_page

    Loan
    |> preload(:client)
    |> order_by([l], desc: l.inserted_at)
    |> limit(^per_page)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc "Returns loans for a client, ordered newest-first, with payments preloaded."
  def get_loans_for_client(client_id) do
    Loan
    |> where([l], l.client_id == ^client_id)
    |> order_by([l], desc: l.inserted_at)
    |> preload(:payments)
    |> Repo.all()
  end

  def get_loan!(id), do: Repo.get!(Loan, id)

  @doc """
  Returns compound interest details for a loan.
  See `LoanSystem.Loans.InterestCalculator.calculate/1` for the returned map keys.
  """
  def compound_interest_details(%Loan{} = loan) do
    InterestCalculator.calculate(loan)
  end

  # ---------------------------------------------------------------------------
  # Loan mutations
  # ---------------------------------------------------------------------------

  @doc """
  Creates a loan and atomically recalculates the owning client's stats
  (total_loans, current_balance).
  """
  def create_loan(attrs \\ %{}) do
    with :ok <- check_pending_loan(attrs),
         :ok <- check_rejection_cooldown(attrs) do
      client_id = Map.get(attrs, :client_id) || Map.get(attrs, "client_id")
      amount    = Map.get(attrs, :amount)    || Map.get(attrs, "amount")
      {risk_level, _score, _signals} = FraudDetector.evaluate(client_id, amount)
      attrs = Map.put(attrs, "risk_level", risk_level)

      Ecto.Multi.new()
      |> Ecto.Multi.insert(:loan, Loan.changeset(%Loan{}, attrs))
      |> Ecto.Multi.run(:update_client_stats, fn repo, %{loan: loan} ->
        recalculate_client_stats(repo, loan.client_id)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{loan: loan}}              -> {:ok, loan}
        {:error, :loan, changeset, _}     -> {:error, changeset}
        {:error, _, reason, _}            -> {:error, reason}
      end
    end
  end

  @doc """
  Returns a list of fraud signal strings for an existing loan.
  Delegates to FraudDetector so all scoring logic lives in one place.
  """
  def fraud_signals(%Loan{id: loan_id, client_id: client_id, amount: amount}) do
    {_level, _score, signals} = FraudDetector.evaluate(client_id, amount, loan_id)
    signals
  end

  def update_loan(%Loan{} = loan, attrs) do
    loan
    |> Loan.changeset(attrs)
    |> Repo.update()
  end

  def delete_loan(%Loan{} = loan) do
    Ecto.Multi.new()
    |> Ecto.Multi.delete(:loan, loan)
    |> Ecto.Multi.run(:update_client_stats, fn repo, _ ->
      recalculate_client_stats(repo, loan.client_id)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{loan: deleted}}        -> {:ok, deleted}
      {:error, :loan, changeset, _}  -> {:error, changeset}
      {:error, _, reason, _}         -> {:error, reason}
    end
  end

  # Loan approval — recalculates client stats since status change affects balance sum
  def approve_loan(%Loan{} = loan) do
    result =
      loan
      |> Loan.changeset(%{
        status: "approved",
        approved_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      })
      |> Repo.update()

    with {:ok, updated} <- result do
      recalculate_client_stats(Repo, updated.client_id)
      generate_repayment_schedule(updated)
      {:ok, updated}
    end
  end

  @doc """
  Generates the loan's installment schedule as one "pending" Payment row
  per month, due monthly from the approval date, using the fixed
  monthly payment InterestCalculator computes. These are planning/arrears
  records only — they never touch remaining_balance; only create_payment/1
  (an admin recording money actually received) does that. Called
  automatically by approve_loan/1; safe to call again (no-ops if a
  schedule already exists for this loan).
  """
  def generate_repayment_schedule(%Loan{status: "approved", approved_at: approved_at} = loan) do
    if list_payments_for_loan(loan.id) == [] do
      %{monthly_payment: monthly_payment} = InterestCalculator.calculate(loan)
      approved_date = NaiveDateTime.to_date(approved_at)
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      installments =
        for n <- 1..loan.term_months do
          %{
            id: Ecto.UUID.generate(),
            amount: monthly_payment,
            due_date: Timex.shift(approved_date, months: n),
            status: "pending",
            loan_id: loan.id,
            inserted_at: now,
            updated_at: now
          }
        end

      Repo.insert_all(Payment, installments)
    end

    :ok
  end

  # Loan rejection — removes loan from active balance sum
  def reject_loan(%Loan{} = loan) do
    result =
      loan
      |> Loan.changeset(%{status: "rejected"})
      |> Repo.update()

    with {:ok, updated} <- result do
      recalculate_client_stats(Repo, updated.client_id)
      {:ok, updated}
    end
  end

  # ---------------------------------------------------------------------------
  # Payment queries
  # ---------------------------------------------------------------------------

  def list_payments_for_loan(loan_id) do
    Payment
    |> where([p], p.loan_id == ^loan_id)
    |> order_by([p], asc: p.payment_date)
    |> Repo.all()
  end

  def get_payment!(id), do: Repo.get!(Payment, id)

  @doc """
  Returns pending upcoming payments for a client, ordered by payment_date.
  Uses the composite index on (loan_id, status, payment_date).
  """
  def get_upcoming_payments(client_id) do
    today = Date.utc_today()

    # Pending (unpaid) installments are tracked by due_date — payment_date
    # is only set once a payment is actually recorded, so a pending
    # installment normally has payment_date: nil and would never match a
    # payment_date filter.
    Payment
    |> join(:inner, [p], l in assoc(p, :loan))
    |> where([p, l], l.client_id == ^client_id)
    |> where([p], p.status == "pending" and p.due_date >= ^today)
    |> order_by([p], p.due_date)
    |> preload(:loan)
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Payment mutations
  # ---------------------------------------------------------------------------

  @doc """
  Creates a payment. Validates that the amount does not exceed the loan's
  remaining balance, then atomically:
    1. Inserts the payment record
    2. Deducts the amount from the loan's remaining_balance (marks loan
       "completed" when balance reaches zero)
    3. Recalculates the client's current_balance
  """
  def create_payment(attrs \\ %{}) do
    with :ok <- check_payment_amount(attrs) do
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:payment, Payment.changeset(%Payment{}, attrs))
      |> Ecto.Multi.run(:update_loan_balance, fn repo, %{payment: payment} ->
        loan = repo.get!(Loan, payment.loan_id)
        new_balance = Decimal.sub(loan.remaining_balance, payment.amount)
        new_status  =
          if Decimal.compare(new_balance, Decimal.new("0")) == :eq,
            do: "completed",
            else: loan.status

        loan
        |> Loan.changeset(%{remaining_balance: new_balance, status: new_status})
        |> repo.update()
      end)
      |> Ecto.Multi.run(:update_client_stats, fn repo, %{update_loan_balance: loan} ->
        recalculate_client_stats(repo, loan.client_id)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{payment: payment}}          -> {:ok, payment}
        {:error, :payment, changeset, _}    -> {:error, changeset}
        {:error, _, reason, _}              -> {:error, reason}
      end
    end
  end

  def update_payment(%Payment{} = payment, attrs) do
    payment
    |> Payment.changeset(attrs)
    |> Repo.update()
  end

  # ---------------------------------------------------------------------------
  # Collateral
  # ---------------------------------------------------------------------------

  def list_collaterals_for_loan(loan_id) do
    Collateral
    |> where([c], c.loan_id == ^loan_id)
    |> order_by([c], asc: c.inserted_at)
    |> Repo.all()
  end

  def get_collateral!(id), do: Repo.get!(Collateral, id)

  def create_collateral(attrs \\ %{}) do
    %Collateral{}
    |> Collateral.changeset(attrs)
    |> Repo.insert()
  end

  def delete_collateral(%Collateral{} = collateral), do: Repo.delete(collateral)

  def total_collateral_value(loan_id) do
    from(c in Collateral,
      where: c.loan_id == ^loan_id,
      select: coalesce(sum(c.estimated_value), ^Decimal.new("0.00"))
    )
    |> Repo.one()
  end

  def count_loans, do: Repo.aggregate(Loan, :count)

  def count_active_loans do
    from(l in Loan, where: l.status in ["pending", "approved"])
    |> Repo.aggregate(:count)
  end

  def total_outstanding_balance do
    from(l in Loan,
      where: l.status in ["pending", "approved"],
      select: coalesce(sum(l.remaining_balance), ^Decimal.new("0.00"))
    )
    |> Repo.one()
  end

  # ---------------------------------------------------------------------------
  # Arrears
  # ---------------------------------------------------------------------------

  @doc """
  Flips every "pending" installment whose due_date has passed to
  "overdue". Called periodically by LoanSystem.ArrearsScheduler; also
  safe to call directly (e.g. from an admin action or a test). Returns
  the number of payments flipped.
  """
  def mark_overdue_payments do
    today = Date.utc_today()

    {count, _} =
      from(p in Payment, where: p.status == "pending" and p.due_date < ^today)
      |> Repo.update_all(set: [status: "overdue"])

    count
  end

  @doc "Count of overdue installments, optionally scoped to one client."
  def count_overdue_payments(client_id \\ nil) do
    Payment
    |> maybe_join_client(client_id)
    |> where([p], p.status == "overdue")
    |> Repo.aggregate(:count)
  end

  @doc "Total ZMW value of all overdue installments, optionally scoped to one client."
  def total_overdue_amount(client_id \\ nil) do
    Payment
    |> maybe_join_client(client_id)
    |> where([p], p.status == "overdue")
    |> select([p], coalesce(sum(p.amount), ^Decimal.new("0.00")))
    |> Repo.one()
  end

  defp maybe_join_client(query, nil), do: query

  defp maybe_join_client(query, client_id) do
    query
    |> join(:inner, [p], l in assoc(p, :loan))
    |> where([p, l], l.client_id == ^client_id)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Validates that the payment amount does not exceed the loan's remaining balance.
  # Called in create_payment before the Multi begins.
  defp check_payment_amount(attrs) do
    loan_id = Map.get(attrs, :loan_id) || Map.get(attrs, "loan_id")
    amount  = Map.get(attrs, :amount)  || Map.get(attrs, "amount")

    with true <- not is_nil(loan_id) and not is_nil(amount),
         loan when not is_nil(loan) <- Repo.get(Loan, loan_id) do
      decimal_amount =
        if is_struct(amount, Decimal), do: amount, else: Decimal.new(to_string(amount))

      if Decimal.compare(decimal_amount, loan.remaining_balance) == :gt do
        {:error, :amount_exceeds_balance}
      else
        :ok
      end
    else
      false -> :ok  # missing attrs; let changeset handle required fields
      nil   -> :ok  # missing loan; FK constraint will catch this
    end
  end

  # ---------------------------------------------------------------------------
  # Phase 1 fraud guards — called before create_loan persists anything
  # ---------------------------------------------------------------------------

  # Hard block: client already has a loan waiting for a decision.
  defp check_pending_loan(attrs) do
    client_id = Map.get(attrs, :client_id) || Map.get(attrs, "client_id")

    if is_nil(client_id) do
      :ok
    else
      count =
        from(l in Loan,
          where: l.client_id == ^client_id and l.status == "pending",
          select: count(l.id)
        )
        |> Repo.one()

      if count > 0, do: {:error, :pending_loan_exists}, else: :ok
    end
  end

  # Hard block: client had a loan rejected within the last 30 days.
  defp check_rejection_cooldown(attrs) do
    client_id = Map.get(attrs, :client_id) || Map.get(attrs, "client_id")

    if is_nil(client_id) do
      :ok
    else
      cutoff =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-30 * 24 * 60 * 60, :second)
        |> NaiveDateTime.truncate(:second)

      count =
        from(l in Loan,
          where:
            l.client_id == ^client_id and
              l.status == "rejected" and
              l.updated_at >= ^cutoff,
          select: count(l.id)
        )
        |> Repo.one()

      if count > 0, do: {:error, :rejection_cooldown}, else: :ok
    end
  end

  # Recalculates a client's total_loans and current_balance from the DB.
  # Accepts either the LoanSystem.Repo module or the repo passed inside Ecto.Multi.
  defp recalculate_client_stats(repo, client_id) do
    balance =
      from(l in Loan,
        where: l.client_id == ^client_id and l.status in ["pending", "approved"],
        select: sum(l.remaining_balance)
      )
      |> repo.one()
      |> then(fn
        nil -> Decimal.new("0.00")
        val -> val
      end)

    count =
      from(l in Loan, where: l.client_id == ^client_id, select: count(l.id))
      |> repo.one()

    from(c in Client, where: c.id == ^client_id)
    |> repo.update_all(set: [current_balance: balance, total_loans: count])

    {:ok, :updated}
  end
end
