defmodule LoanSystem.Loans do
  import Ecto.Query
  alias LoanSystem.Repo
  alias LoanSystem.Loans.{Loan, Payment, InterestCalculator}
  alias LoanSystem.Clients.Client

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
      {:ok, updated}
    end
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

    Payment
    |> join(:inner, [p], l in assoc(p, :loan))
    |> where([p, l], l.client_id == ^client_id)
    |> where([p], p.status == "pending" and p.payment_date >= ^today)
    |> order_by([p], p.payment_date)
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
