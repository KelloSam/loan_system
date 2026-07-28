defmodule MiwayCreditCore.Applications do
  @moduledoc """
  The request-and-decision half of the domain, plus the collateral
  pledged to secure an approved loan. Approving an application is the
  one moment that creates a LoanAccount, generates its repayment
  schedule, and posts the opening disbursement ledger entry — all in
  one transaction, so an account never exists half-formed.

  Collateral lives here rather than as its own top-level context: it's
  supporting information for a granted application with no proven
  independent lifecycle yet (no valuation, custody, or lien tracking).
  Promote it out only if that changes — see
  `docs/architecture/context_boundaries.md`.
  """

  import Ecto.Query
  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.Applications.{LoanApplication, Collateral}
  alias MiwayCreditCore.Customers
  alias MiwayCreditCore.Customers.CustomerStats
  alias MiwayCreditCore.Lending.{LoanAccount, RepaymentScheduleInstallment, InterestCalculator}
  alias MiwayCreditCore.Accounting.AccountingEntry
  alias MiwayCreditCore.Accounts.Scope
  alias MiwayCreditCore.Authorization
  alias MiwayCreditCore.Risk

  # ---------------------------------------------------------------------------
  # Queries
  # ---------------------------------------------------------------------------

  @doc "Paginated applications, newest first, customer + loan_account preloaded (the admin list view shows the account's status/rate once approved). Accepts page:/per_page:."
  def list_applications(%Scope{} = scope, opts \\ []) do
    page     = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 50)
    offset   = (page - 1) * per_page

    LoanApplication
    |> scope_organisation(scope)
    |> preload([:customer, :loan_account])
    |> order_by([a], desc: a.inserted_at)
    |> limit(^per_page)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc "Applications for a customer, newest first, loan_account preloaded."
  def get_applications_for_customer(%Scope{} = scope, customer_id) do
    LoanApplication
    |> scope_organisation(scope)
    |> where([a], a.customer_id == ^customer_id)
    |> order_by([a], desc: a.inserted_at)
    |> preload(:loan_account)
    |> Repo.all()
  end

  @doc "Fetches an application by id, scoped — one belonging to a different organisation raises the same NoResultsError as an unknown id."
  def get_application!(%Scope{} = scope, id) do
    LoanApplication
    |> scope_organisation(scope)
    |> Repo.get!(id)
    |> Repo.preload([:customer, :loan_account])
  end

  def count_applications(%Scope{} = scope) do
    LoanApplication
    |> scope_organisation(scope)
    |> Repo.aggregate(:count)
  end

  def count_active_applications(%Scope{} = scope) do
    LoanApplication
    |> scope_organisation(scope)
    |> where([a], a.status == "pending")
    |> Repo.aggregate(:count)
  end

  # ---------------------------------------------------------------------------
  # Mutations
  # ---------------------------------------------------------------------------

  @doc """
  Submits a loan application and atomically recalculates the owning
  customer's stats (total_loans). organisation_id is never taken from
  attrs — it's derived from the customer being applied for
  (Customers.get_customer!/2, itself scoped), so an application can
  only ever be filed for a customer already within the caller's
  organisation. created_by_id comes from scope.user — never from
  attrs either — so it can't be spoofed to fake who the maker was for
  maker-checker purposes at approval time.
  """
  def create_application(%Scope{} = scope, attrs \\ %{}) do
    attrs = stringify_keys(attrs)
    customer_id = attrs["customer_id"]

    with :ok <- check_pending_application(customer_id),
         :ok <- check_rejection_cooldown(customer_id) do
      customer = customer_id && Customers.get_customer!(scope, customer_id)
      amount = attrs["requested_amount"]
      {risk_level, risk_score, _signals} = Risk.evaluate(customer_id, amount)

      attrs =
        attrs
        |> Map.put("risk_level", risk_level)
        |> Map.put("risk_score", risk_score)
        |> Map.put("organisation_id", customer && customer.organisation_id)
        |> Map.put("created_by_id", scope.user && scope.user.id)

      Ecto.Multi.new()
      |> Ecto.Multi.insert(:application, LoanApplication.changeset(%LoanApplication{}, attrs))
      |> Ecto.Multi.run(:update_customer_stats, fn repo, %{application: application} ->
        CustomerStats.recalculate(repo, application.customer_id)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{application: application}}    -> {:ok, application}
        {:error, :application, changeset, _}  -> {:error, changeset}
        {:error, _, reason, _}                -> {:error, reason}
      end
    end
  end

  @doc "Fraud signal strings for an existing application. Delegates to Risk."
  def fraud_signals(%LoanApplication{id: id, customer_id: customer_id, requested_amount: amount}) do
    {_level, _score, signals} = Risk.evaluate(customer_id, amount, id)
    signals
  end

  @doc """
  Edits a not-yet-decided application. Uses the submission changeset,
  which never casts :status/:decided_at/:decided_by_id — so this can't
  be used to sneak a decision through, regardless of what a caller puts
  in attrs.
  """
  def update_application(%LoanApplication{} = application, attrs) do
    application
    |> LoanApplication.changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes an application and recalculates the owning customer's stats."
  def delete_application(%LoanApplication{} = application) do
    Ecto.Multi.new()
    |> Ecto.Multi.delete(:application, application)
    |> Ecto.Multi.run(:update_customer_stats, fn repo, _ ->
      CustomerStats.recalculate(repo, application.customer_id)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{application: deleted}}       -> {:ok, deleted}
      {:error, :application, changeset, _} -> {:error, changeset}
      {:error, _, reason, _}               -> {:error, reason}
    end
  end

  @doc """
  Approves a pending application: creates its LoanAccount, generates the
  repayment schedule, posts the opening disbursement ledger entry, and
  recalculates customer stats — all in one transaction. `application`
  must already be a caller-scoped struct (fetched via get_application!/2)
  — every record this creates derives organisation_id from it directly,
  not from a fresh scope, so approval can't cross an organisation
  boundary even if called with a stale reference.

  Two checks happen before any write: maker-checker (the approver
  can't be the same person who submitted the application — a nil
  created_by_id, from before this was tracked, never blocks anyone,
  since there's no maker on record to conflict with) and the
  approver's ApprovalLimit for "applications.approve", if their role
  carries one.
  """
  def approve_application(%LoanApplication{} = application, %Scope{} = scope) do
    with :ok <- check_maker_checker(application, scope),
         :ok <- check_approval_limit(application, scope) do
      do_approve_application(application, scope.user.id)
    end
  end

  defp check_maker_checker(%LoanApplication{created_by_id: nil}, _scope), do: :ok

  defp check_maker_checker(%LoanApplication{created_by_id: created_by_id}, %Scope{user: %{id: user_id}}) do
    if created_by_id == user_id, do: {:error, :maker_checker_violation}, else: :ok
  end

  defp check_approval_limit(%LoanApplication{requested_amount: amount}, scope) do
    case Authorization.approval_limit(scope, "applications.approve") do
      nil -> :ok
      limit -> if Decimal.compare(amount, limit) == :gt, do: {:error, :exceeds_approval_limit}, else: :ok
    end
  end

  defp do_approve_application(%LoanApplication{} = application, admin_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    interest_rate = default_interest_rate()

    %{total_repayment: total_repayment} =
      InterestCalculator.calculate(%{
        amount: application.requested_amount,
        interest_rate: interest_rate,
        term_months: application.requested_term_months
      })

    Ecto.Multi.new()
    |> Ecto.Multi.update(:application, LoanApplication.decision_changeset(application, %{
      status: "approved",
      decided_at: now,
      decided_by_id: admin_id
    }))
    |> Ecto.Multi.insert(:account, fn %{application: application} ->
      LoanAccount.changeset(%LoanAccount{}, %{
        organisation_id: application.organisation_id,
        loan_application_id: application.id,
        customer_id: application.customer_id,
        principal_amount: application.requested_amount,
        interest_rate: interest_rate,
        term_months: application.requested_term_months,
        opened_at: now,
        status: "active",
        # The account owes the full scheduled repayment (principal +
        # interest), not just the principal disbursed — this is what
        # reconciles against the sum of repayment_schedule_installments
        # and is what a customer actually needs to pay to close the loan.
        outstanding_balance: total_repayment
      })
    end)
    |> Ecto.Multi.insert(:disbursement, fn %{account: account} ->
      AccountingEntry.changeset(%AccountingEntry{}, %{
        organisation_id: account.organisation_id,
        loan_account_id: account.id,
        entry_type: "disbursement",
        amount: total_repayment,
        running_balance: total_repayment,
        source_type: "loan_account",
        source_id: account.id,
        description: "Loan disbursed (principal + scheduled interest)",
        occurred_at: now
      })
    end)
    |> Ecto.Multi.run(:schedule, fn repo, %{account: account} ->
      generate_repayment_schedule(repo, account)
    end)
    |> Ecto.Multi.run(:update_customer_stats, fn repo, %{account: account} ->
      CustomerStats.recalculate(repo, account.customer_id)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{application: application, account: account}} -> {:ok, application, account}
      {:error, :application, changeset, _}                 -> {:error, changeset}
      {:error, _, reason, _}                                -> {:error, reason}
    end
  end

  @doc """
  Rejects a pending application. Same maker-checker guard as approval
  — the person who submitted it can't be the one who decides it,
  either way. Recalculates customer stats (no-op today, kept for symmetry).
  """
  def reject_application(%LoanApplication{} = application, %Scope{} = scope, reason) do
    with :ok <- check_maker_checker(application, scope) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      result =
        application
        |> LoanApplication.decision_changeset(%{
          status: "rejected",
          decided_at: now,
          decided_by_id: scope.user.id,
          rejection_reason: reason
        })
        |> Repo.update()

      with {:ok, updated} <- result do
        CustomerStats.recalculate(updated.customer_id)
        {:ok, updated}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Collateral — attaches only to an approved LoanAccount
  # ---------------------------------------------------------------------------

  def list_collaterals_for_account(%Scope{} = scope, loan_account_id) do
    Collateral
    |> scope_organisation(scope)
    |> where([c], c.loan_account_id == ^loan_account_id)
    |> order_by([c], asc: c.inserted_at)
    |> Repo.all()
  end

  def get_collateral!(%Scope{} = scope, id) do
    Collateral
    |> scope_organisation(scope)
    |> Repo.get!(id)
  end

  @doc "organisation_id derives from the LoanAccount it secures, never from attrs."
  def create_collateral(%LoanAccount{} = account, attrs) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.put("loan_account_id", account.id)
      |> Map.put("organisation_id", account.organisation_id)

    %Collateral{}
    |> Collateral.changeset(attrs)
    |> Repo.insert()
  end

  def delete_collateral(%Collateral{} = collateral), do: Repo.delete(collateral)

  def total_collateral_value(%Scope{} = scope, loan_account_id) do
    Collateral
    |> scope_organisation(scope)
    |> where([c], c.loan_account_id == ^loan_account_id)
    |> select([c], coalesce(sum(c.estimated_value), ^Decimal.new("0.00")))
    |> Repo.one()
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp scope_organisation(query, %Scope{organisation_id: :all}), do: query
  defp scope_organisation(query, %Scope{organisation_id: organisation_id}) do
    where(query, organisation_id: ^organisation_id)
  end

  defp stringify_keys(attrs), do: Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

  # Interest rate isn't collected on the application form today (the old
  # Loan schema took it directly from admin input on create) — kept as a
  # fixed default here so approval has a rate to lock in. Swap for a
  # per-application field or a risk-based rate table when that's designed.
  defp default_interest_rate, do: Decimal.new("18.00")

  defp generate_repayment_schedule(repo, %LoanAccount{} = account) do
    %{monthly_payment: monthly_payment} =
      InterestCalculator.calculate(%{
        amount: account.principal_amount,
        interest_rate: account.interest_rate,
        term_months: account.term_months
      })

    monthly_rate = Decimal.div(account.interest_rate, Decimal.new("1200"))
    # RepaymentScheduleInstallment's timestamps() defaults to
    # :naive_datetime — insert_all bypasses changesets/schema casting,
    # so this must already match that type, not a DateTime.
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    {installments, _} =
      Enum.map_reduce(1..account.term_months, account.principal_amount, fn n, remaining_principal ->
        interest_due = remaining_principal |> Decimal.mult(monthly_rate) |> Decimal.round(2)
        principal_due =
          if n == account.term_months do
            remaining_principal
          else
            monthly_payment |> Decimal.sub(interest_due) |> Decimal.round(2)
          end

        row = %{
          id: Ecto.UUID.generate(),
          organisation_id: account.organisation_id,
          loan_account_id: account.id,
          installment_number: n,
          due_date: Timex.shift(DateTime.to_date(account.opened_at), months: n),
          scheduled_amount: Decimal.add(principal_due, interest_due),
          scheduled_principal: principal_due,
          scheduled_interest: interest_due,
          paid_amount: Decimal.new("0.00"),
          status: "upcoming",
          inserted_at: now,
          updated_at: now
        }

        {row, Decimal.sub(remaining_principal, principal_due)}
      end)

    repo.insert_all(RepaymentScheduleInstallment, installments)
    {:ok, :scheduled}
  end

  defp check_pending_application(nil), do: :ok

  defp check_pending_application(customer_id) do
    count =
      from(a in LoanApplication,
        where: a.customer_id == ^customer_id and a.status == "pending",
        select: count(a.id)
      )
      |> Repo.one()

    if count > 0, do: {:error, :pending_application_exists}, else: :ok
  end

  defp check_rejection_cooldown(nil), do: :ok

  defp check_rejection_cooldown(customer_id) do
    cutoff =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.add(-30 * 24 * 60 * 60, :second)
      |> NaiveDateTime.truncate(:second)

    count =
      from(a in LoanApplication,
        where:
          a.customer_id == ^customer_id and
            a.status == "rejected" and
            a.updated_at >= ^cutoff,
        select: count(a.id)
      )
      |> Repo.one()

    if count > 0, do: {:error, :rejection_cooldown}, else: :ok
  end
end
