defmodule MiwayCreditCore.Applications do
  @moduledoc """
  The request-and-decision half of the domain, plus the collateral
  pledged to secure a disbursed loan. The lifecycle is a real state
  machine — pending -> under_review -> approved/rejected, with
  approved -> disbursed as its own separate step — see
  assess_application/3, approve_application/2, disburse_application/2,
  reject_application/3, withdraw_application/2. Disbursing is the one
  moment that creates a LoanAccount, generates its repayment schedule,
  and posts the opening disbursement ledger entry — all in one
  transaction, so an account never exists half-formed. Approving alone
  never does: a credit decision and the actual release of funds are
  never the same instant.

  Collateral lives here rather than as its own top-level context: it's
  supporting information for a granted application with no proven
  independent lifecycle yet (no valuation, custody, or lien tracking).
  Promote it out only if that changes — see
  `docs/architecture/context_boundaries.md`.
  """

  import Ecto.Query
  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.Applications.{LoanApplication, Collateral, ApprovalDecision}
  alias MiwayCreditCore.Customers
  alias MiwayCreditCore.Customers.CustomerStats
  alias MiwayCreditCore.Lending.{LoanAccount, RepaymentScheduleInstallment, InterestCalculator}
  alias MiwayCreditCore.Accounting.{AccountingEntry, GeneralLedger}
  alias MiwayCreditCore.Accounts.Scope
  alias MiwayCreditCore.Authorization
  alias MiwayCreditCore.CreditReporting
  alias MiwayCreditCore.Products
  alias MiwayCreditCore.Products.LoanProduct
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
    |> Repo.preload([:customer, :loan_account, approval_decisions: :decided_by])
  end

  def count_applications(%Scope{} = scope) do
    LoanApplication
    |> scope_organisation(scope)
    |> Repo.aggregate(:count)
  end

  def count_active_applications(%Scope{} = scope) do
    LoanApplication
    |> scope_organisation(scope)
    |> where([a], a.status in ["pending", "under_review", "referred"])
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
    amount = to_decimal(attrs["requested_amount"])
    term_months = to_integer(attrs["requested_term_months"])

    with :ok <- check_pending_application(customer_id),
         :ok <- check_rejection_cooldown(customer_id),
         {:ok, product} <- fetch_available_product(scope, attrs["loan_product_id"]),
         :ok <- check_product_bounds(product, amount, term_months) do
      customer = customer_id && Customers.get_customer!(scope, customer_id)
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
  Moves a pending (or referred) application to under_review — staff
  assessment, decision-ready. "referred" is accepted alongside
  "pending" so resolving a referral (refer_application/3) is just
  re-running assessment once the missing information arrives, not a
  separate function. Notes are optional free text (what the loan
  officer found), surfaced to whoever decides the application next.
  """
  def assess_application(application, scope, notes \\ nil)

  def assess_application(%LoanApplication{status: status} = application, %Scope{} = scope, notes)
      when status in ["pending", "referred"] do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    application
    |> LoanApplication.decision_changeset(%{
      status: "under_review",
      assessed_at: now,
      assessed_by_id: scope.user.id,
      assessment_notes: notes
    })
    |> Repo.update()
  end

  def assess_application(%LoanApplication{}, %Scope{}, _notes), do: {:error, :invalid_status}

  @doc """
  Approves an assessed application at its current level — records the
  credit decision only. Does **not** create a LoanAccount or move any
  money; that happens separately in disburse_application/2, once, and
  only after every required level has concurred. Only an application
  already under_review (i.e. already assessed) can be approved —
  `assess_application/3` must run first.

  `attests_no_conflict_of_interest` must be exactly `true` — the
  decider affirmatively confirming no conflict of interest with this
  applicant before their decision is accepted. There's no data in this
  system to detect a conflict automatically (no staff/customer
  relationship model exists), so this is a self-declaration, not
  automatic detection.

  A product's approval_levels (1, or 2 with `requires_second_level_approval`)
  and, at whichever level is final, a possible committee requirement
  (`requires_committee_decision` — `committee_quorum` distinct
  concurring approvals; `committee_size` is the roster's informational
  size, not separately enforced — since a rejection at any level ends
  the application outright, `committee_quorum` concurring approvals
  always concludes the level before `committee_size` could ever be
  reached) both come from the product. Every check below runs at
  *every* level, not
  just the first: separation of duties (renamed from maker-checker —
  the decider can't be the original submitter, nor anyone who already
  decided an earlier level or already voted at this one; skippable
  per-product via `requires_separation_of_duties`), the ApprovalLimit
  for "applications.approve" if the role carries one, the product's
  guarantor/affordability/CRB requirements, and the level's own
  minimum role. Only once the *final* level's requirement is met does
  `LoanApplication.status` actually flip to `"approved"` — until then
  it stays `under_review`, now just mid-workflow.
  """
  def approve_application(%LoanApplication{status: "under_review"} = application, %Scope{} = scope, attests_no_conflict_of_interest) do
    product = Products.get_product!(scope, application.loan_product_id)
    level = current_level(Repo, application, product)

    with :ok <- check_conflict_of_interest_attestation(attests_no_conflict_of_interest),
         :ok <- check_separation_of_duties(application, scope, product),
         :ok <- check_not_already_decided(application, scope),
         :ok <- check_approval_limit(application, scope),
         :ok <- check_guarantor_requirement(application, product, scope),
         :ok <- check_level_minimum_role(product, scope, level),
         :ok <- check_affordability(application, product, scope),
         :ok <- check_crb_requirement(application, product, scope) do
      record_level_decision(application, scope, product, level, %{decision: "approved"})
    end
  end

  def approve_application(%LoanApplication{}, %Scope{}, _attestation), do: {:error, :invalid_status}

  @doc """
  Conditionally approves an assessed application — same guard chain as
  approve_application/3, but always ends the workflow immediately
  (like reject_application/4, and unlike a plain approval it never
  waits on a second level or committee quorum: whoever conditionally
  approves is giving the final word, just one with strings attached).
  `LoanApplication.status` becomes "approved" with `conditions` set;
  `disburse_application/2` refuses until `clear_conditions/2` confirms
  they were met.
  """
  def conditionally_approve_application(%LoanApplication{status: "under_review"} = application, %Scope{} = scope, conditions, attests_no_conflict_of_interest)
      when is_binary(conditions) and conditions != "" do
    product = Products.get_product!(scope, application.loan_product_id)
    level = current_level(Repo, application, product)

    with :ok <- check_conflict_of_interest_attestation(attests_no_conflict_of_interest),
         :ok <- check_separation_of_duties(application, scope, product),
         :ok <- check_not_already_decided(application, scope),
         :ok <- check_approval_limit(application, scope),
         :ok <- check_guarantor_requirement(application, product, scope),
         :ok <- check_level_minimum_role(product, scope, level),
         :ok <- check_affordability(application, product, scope),
         :ok <- check_crb_requirement(application, product, scope) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Ecto.Multi.new()
      |> Ecto.Multi.insert(:decision, ApprovalDecision.changeset(%ApprovalDecision{}, %{
        organisation_id: application.organisation_id,
        loan_application_id: application.id,
        decided_by_id: scope.user.id,
        level: level,
        decision: "conditional",
        conditions: conditions,
        decided_at: now
      }))
      |> Ecto.Multi.update(:application, LoanApplication.decision_changeset(application, %{
        status: "approved",
        decided_at: now,
        decided_by_id: scope.user.id,
        conditions: conditions
      }))
      |> Repo.transaction()
      |> case do
        {:ok, %{application: updated}} -> {:ok, updated}
        {:error, _, reason, _}         -> {:error, reason}
      end
    end
  end

  def conditionally_approve_application(%LoanApplication{}, %Scope{}, _conditions, _attestation), do: {:error, :invalid_status}

  @doc """
  Confirms a conditionally-approved application's conditions were
  actually met, unblocking disburse_application/2. A deliberate,
  separate staff action — disbursement never infers a condition was
  satisfied on its own.
  """
  def clear_conditions(%LoanApplication{conditions: conditions, conditions_cleared_at: nil} = application, %Scope{})
      when not is_nil(conditions) do
    application
    |> LoanApplication.decision_changeset(%{
      status: application.status,
      conditions_cleared_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  def clear_conditions(%LoanApplication{}, %Scope{}), do: {:error, :no_conditions_to_clear}

  @doc """
  Refers an assessed application back for more information —
  under_review only, requires a reason (what's missing). Not a credit
  decision, so no separation-of-duties or attestation gate — the same
  person who submitted or previously assessed it can refer it.
  Resolving a referral reuses assess_application/3 (its guard accepts
  "referred" alongside "pending") rather than a dedicated function:
  re-assessing once the missing information arrives is exactly what
  that already means.
  """
  def refer_application(%LoanApplication{status: "under_review"} = application, %Scope{} = scope, reason)
      when is_binary(reason) and reason != "" do
    product = Products.get_product!(scope, application.loan_product_id)
    level = current_level(Repo, application, product)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:decision, ApprovalDecision.changeset(%ApprovalDecision{}, %{
      organisation_id: application.organisation_id,
      loan_application_id: application.id,
      decided_by_id: scope.user.id,
      level: level,
      decision: "referred",
      notes: reason,
      decided_at: now
    }))
    |> Ecto.Multi.update(:application, LoanApplication.decision_changeset(application, %{status: "referred"}))
    |> Repo.transaction()
    |> case do
      {:ok, %{application: updated}} -> {:ok, updated}
      {:error, _, reason, _}         -> {:error, reason}
    end
  end

  def refer_application(%LoanApplication{}, %Scope{}, _reason), do: {:error, :invalid_status}

  # Inserts this level's ApprovalDecision and, only if that concurrence
  # completes the *final* required level, flips the application to
  # approved in the same transaction — otherwise the application stays
  # under_review, now one level further along.
  defp record_level_decision(application, scope, product, level, decision_attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:decision, ApprovalDecision.changeset(%ApprovalDecision{}, Map.merge(%{
      organisation_id: application.organisation_id,
      loan_application_id: application.id,
      decided_by_id: scope.user.id,
      level: level,
      decided_at: now
    }, decision_attrs)))
    |> Ecto.Multi.run(:application, fn repo, _changes ->
      if final_level?(product, level) and level_requirement_met?(repo, application.id, level, product) do
        application
        |> LoanApplication.decision_changeset(%{status: "approved", decided_at: now, decided_by_id: scope.user.id})
        |> repo.update()
      else
        {:ok, application}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{application: updated}} -> {:ok, updated}
      {:error, _, reason, _}         -> {:error, reason}
    end
  end

  defp check_conflict_of_interest_attestation(true), do: :ok
  defp check_conflict_of_interest_attestation(_), do: {:error, :conflict_of_interest_attestation_required}

  defp check_separation_of_duties(_application, _scope, %LoanProduct{requires_separation_of_duties: false}), do: :ok
  defp check_separation_of_duties(%LoanApplication{created_by_id: nil}, _scope, _product), do: :ok

  defp check_separation_of_duties(%LoanApplication{created_by_id: created_by_id}, %Scope{user: %{id: user_id}}, _product) do
    if created_by_id == user_id, do: {:error, :maker_checker_violation}, else: :ok
  end

  # Nobody decides the same application twice, whether that's two
  # levels or two committee seats — this is both the multi-level
  # integrity control and a conflict-of-interest guard broader than
  # plain separation of duties.
  # "referred" is deliberately excluded — it's not a vote in the
  # approval-workflow sense, just "not ready yet, come back once X
  # arrives." Once a referral is resolved (assess_application/3
  # again), the same person who referred it is free to decide it.
  defp check_not_already_decided(application, %Scope{user: %{id: user_id}}) do
    already_decided =
      ApprovalDecision
      |> where([d], d.loan_application_id == ^application.id and d.decided_by_id == ^user_id and d.decision != "referred")
      |> Repo.exists?()

    if already_decided, do: {:error, :already_decided}, else: :ok
  end

  defp check_approval_limit(%LoanApplication{requested_amount: amount}, scope) do
    case Authorization.approval_limit(scope, "applications.approve") do
      nil -> :ok
      limit -> if Decimal.compare(amount, limit) == :gt, do: {:error, :exceeds_approval_limit}, else: :ok
    end
  end

  defp check_guarantor_requirement(_application, %LoanProduct{requires_guarantor: false}, _scope), do: :ok

  defp check_guarantor_requirement(application, %LoanProduct{requires_guarantor: true} = product, scope) do
    count = scope |> Customers.list_guarantors_for_customer(application.customer_id) |> length()
    if count >= product.minimum_guarantors, do: :ok, else: {:error, :guarantor_required}
  end

  defp check_level_minimum_role(product, scope, level) do
    role = level_minimum_role(product, level)
    if Authorization.role_meets_minimum?(scope, role), do: :ok, else: {:error, :insufficient_approval_role}
  end

  defp level_minimum_role(product, 1), do: product.minimum_approval_role
  defp level_minimum_role(product, 2), do: product.second_level_minimum_role || product.minimum_approval_role

  # 1, or 2 when the product requires a second level.
  defp total_levels(%LoanProduct{requires_second_level_approval: true}), do: 2
  defp total_levels(%LoanProduct{}), do: 1

  defp final_level?(product, level), do: level == total_levels(product)

  # Committee agreement (committee_quorum concurring approvals) only
  # applies at whichever level is final; every other level needs
  # exactly one.
  defp required_votes_for_level(product, level) do
    if product.requires_committee_decision and final_level?(product, level) do
      product.committee_quorum
    else
      1
    end
  end

  defp level_requirement_met?(repo, application_id, level, product) do
    approved_count =
      ApprovalDecision
      |> where([d], d.loan_application_id == ^application_id and d.level == ^level and d.decision == "approved")
      |> repo.aggregate(:count)

    approved_count >= required_votes_for_level(product, level)
  end

  # The lowest level that hasn't yet met its own requirement — where
  # the *next* decision on this application belongs. Derived fresh
  # from approval_decisions every time, not a stored pointer, so it
  # can never drift out of sync with the decisions actually on record.
  defp current_level(repo, application, product) do
    total = total_levels(product)

    Enum.find(1..total, total + 1, fn level ->
      not level_requirement_met?(repo, application.id, level, product)
    end)
  end

  defp check_affordability(_application, %LoanProduct{requires_affordability_check: false}, _scope), do: :ok

  defp check_affordability(application, %LoanProduct{requires_affordability_check: true} = product, scope) do
    Risk.assess_affordability(scope, application, product)
  end

  @crb_report_validity_days 90

  defp check_crb_requirement(_application, %LoanProduct{requires_crb_check: false}, _scope), do: :ok

  defp check_crb_requirement(application, %LoanProduct{requires_crb_check: true}, scope) do
    case CreditReporting.get_latest_report_for_customer(scope, application.customer_id) do
      nil ->
        {:error, :crb_check_required}

      %{outcome: "adverse"} ->
        {:error, :adverse_crb_report}

      %{checked_at: checked_at} ->
        if Date.diff(Date.utc_today(), checked_at) > @crb_report_validity_days do
          {:error, :crb_check_expired}
        else
          :ok
        end
    end
  end

  @doc """
  Disburses an approved application: creates its LoanAccount (with a
  system-generated contract reference and the disbursement's
  method/channel reference — see `LoanAccount.generate_contract_reference/1`),
  generates the repayment schedule, posts the opening disbursement
  ledger entry, and recalculates customer stats — all in one
  transaction, including the application's own transition to
  disbursed. Only an approved application can be disbursed; this is
  deliberately a separate step from the approval decision itself (see
  approve_application/2), so a credit decision and the actual release
  of funds are never the same instant. `application` must already be a
  caller-scoped struct (fetched via get_application!/2) — every record
  this creates derives organisation_id from it directly, not from a
  fresh scope, so disbursement can't cross an organisation boundary
  even if called with a stale reference.

  `disbursement_details` is `%{"method" => ..., "reference" => ...}` —
  "method" defaults to "bank_transfer" for callers that don't care to
  specify it (`cash | bank_transfer | mobile_money | cheque | other`
  otherwise), "reference" optional (the channel's own confirmation
  number, e.g. a mobile money transaction id).
  """
  def disburse_application(application, scope, disbursement_details \\ %{"method" => "bank_transfer"})

  def disburse_application(%LoanApplication{status: "approved"} = application, %Scope{} = scope, disbursement_details) do
    case check_conditions_cleared(application) do
      :ok ->
        product = Products.get_product!(scope, application.loan_product_id)
        do_disburse_application(application, scope.user.id, product, stringify_keys(disbursement_details))

      error ->
        error
    end
  end

  def disburse_application(%LoanApplication{}, %Scope{}, _disbursement_details), do: {:error, :invalid_status}

  defp check_conditions_cleared(%LoanApplication{conditions: nil}), do: :ok
  defp check_conditions_cleared(%LoanApplication{conditions_cleared_at: nil}), do: {:error, :conditions_not_cleared}
  defp check_conditions_cleared(%LoanApplication{}), do: :ok

  defp do_disburse_application(%LoanApplication{} = application, admin_id, %LoanProduct{} = product, disbursement_details) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    account_id = Ecto.UUID.generate()

    %{total_repayment: total_repayment} =
      InterestCalculator.calculate(%{
        amount: application.requested_amount,
        interest_rate: product.interest_rate,
        term_months: application.requested_term_months
      })

    origination_fee =
      product.origination_fee_percent
      |> Decimal.mult(application.requested_amount)
      |> Decimal.div(Decimal.new("100"))
      |> Decimal.round(2)

    cash_account_code = GeneralLedger.cash_account_code(disbursement_details["method"])
    interest_amount = Decimal.sub(total_repayment, application.requested_amount)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:application, LoanApplication.decision_changeset(application, %{
      status: "disbursed",
      disbursed_at: now,
      disbursed_by_id: admin_id
    }))
    |> Ecto.Multi.insert(:account, fn %{application: application} ->
      LoanAccount.changeset(%LoanAccount{id: account_id}, %{
        organisation_id: application.organisation_id,
        loan_application_id: application.id,
        customer_id: application.customer_id,
        loan_product_id: product.id,
        principal_amount: application.requested_amount,
        interest_rate: product.interest_rate,
        interest_method: product.interest_method,
        term_months: application.requested_term_months,
        contract_reference: LoanAccount.generate_contract_reference(account_id),
        disbursement_method: disbursement_details["method"],
        disbursement_reference: disbursement_details["reference"],
        opened_at: now,
        status: "active",
        # The account owes the full scheduled repayment (principal +
        # interest) plus any origination fee, not just the principal
        # disbursed — this is what reconciles against the sum of
        # repayment_schedule_installments plus the fee entry below, and
        # is what a customer actually needs to pay to close the loan.
        outstanding_balance: Decimal.add(total_repayment, origination_fee)
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
    |> GeneralLedger.post_journal_entry(:disbursement_gl, %{
      organisation_id: application.organisation_id,
      description: "Loan disbursed (principal + scheduled interest)",
      source_type: "loan_account",
      source_id: account_id,
      occurred_at: now,
      lines: [
        %{account_code: "1100", debit: total_repayment},
        %{account_code: cash_account_code, credit: application.requested_amount},
        %{account_code: "4000", credit: interest_amount}
      ]
    })
    |> maybe_insert_origination_fee(origination_fee, now, application.organisation_id, account_id)
    |> Ecto.Multi.run(:schedule, fn repo, %{account: account} ->
      generate_repayment_schedule(repo, account, product.grace_period_days)
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

  # Zero-fee products skip this step entirely rather than posting a
  # $0.00 no-op ledger entry. post_journal_entry/3 has the same
  # zero-line skip built in, so the GL call below is safe even when
  # this branch's own check is somehow bypassed.
  defp maybe_insert_origination_fee(multi, origination_fee, now, organisation_id, account_id) do
    if Decimal.compare(origination_fee, Decimal.new("0")) == :gt do
      multi
      |> Ecto.Multi.insert(:origination_fee, fn %{account: account, disbursement: disbursement} ->
        AccountingEntry.changeset(%AccountingEntry{}, %{
          organisation_id: account.organisation_id,
          loan_account_id: account.id,
          entry_type: "fee",
          amount: origination_fee,
          running_balance: Decimal.add(disbursement.running_balance, origination_fee),
          source_type: "loan_account",
          source_id: account.id,
          description: "Origination fee",
          occurred_at: now
        })
      end)
      |> GeneralLedger.post_journal_entry(:origination_fee_gl, %{
        organisation_id: organisation_id,
        description: "Origination fee",
        source_type: "loan_account",
        source_id: account_id,
        occurred_at: now,
        lines: [
          %{account_code: "1100", debit: origination_fee},
          %{account_code: "4100", credit: origination_fee}
        ]
      })
    else
      multi
    end
  end

  @doc """
  Rejects an assessed application — at *any* level, this ends the
  whole workflow immediately regardless of how many approval levels
  remain (no partial-rejection state; one dissent is enough). Same
  separation-of-duties guard as approval, same under_review
  precondition — a decision can't be made before assessment.
  `decline_reason_category` is a fixed category (defaults to "other"
  for callers that don't care to classify it) alongside the existing
  freeform `reason`, kept as the detail text. Recalculates customer
  stats (no-op today, kept for symmetry).
  """
  def reject_application(application, scope, reason, decline_reason_category \\ "other")

  def reject_application(%LoanApplication{status: "under_review"} = application, %Scope{} = scope, reason, decline_reason_category) do
    product = Products.get_product!(scope, application.loan_product_id)
    level = current_level(Repo, application, product)

    with :ok <- check_separation_of_duties(application, scope, product),
         :ok <- check_not_already_decided(application, scope) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Ecto.Multi.new()
      |> Ecto.Multi.insert(:decision, ApprovalDecision.changeset(%ApprovalDecision{}, %{
        organisation_id: application.organisation_id,
        loan_application_id: application.id,
        decided_by_id: scope.user.id,
        level: level,
        decision: "rejected",
        decline_reason_category: decline_reason_category,
        notes: reason,
        decided_at: now
      }))
      |> Ecto.Multi.update(:application, LoanApplication.decision_changeset(application, %{
        status: "rejected",
        decided_at: now,
        decided_by_id: scope.user.id,
        rejection_reason: reason
      }))
      |> Ecto.Multi.run(:update_customer_stats, fn repo, %{application: updated} ->
        CustomerStats.recalculate(repo, updated.customer_id)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{application: updated}} -> {:ok, updated}
        {:error, _, reason, _}         -> {:error, reason}
      end
    end
  end

  def reject_application(%LoanApplication{}, %Scope{}, _reason, _decline_reason_category), do: {:error, :invalid_status}

  @doc """
  Withdraws an application still in flight — pending or under_review.
  Not an approval-style decision by someone else, so no maker-checker
  check: anyone holding applications.withdraw can pull back any
  in-flight application in their organisation. Once a decision has
  been made (approved/rejected) or funds disbursed, withdrawal is no
  longer possible.
  """
  def withdraw_application(%LoanApplication{status: status} = application, %Scope{} = scope)
      when status in ["pending", "under_review"] do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    application
    |> LoanApplication.decision_changeset(%{status: "withdrawn", decided_at: now, decided_by_id: scope.user.id})
    |> Repo.update()
  end

  def withdraw_application(%LoanApplication{}, %Scope{}), do: {:error, :invalid_status}

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

  defp generate_repayment_schedule(repo, %LoanAccount{} = account, grace_period_days) do
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

    # The whole schedule is anchored `grace_period_days` after
    # disbursement, not just the first installment — every due date
    # shifts uniformly, the monthly cadence between them is unchanged.
    base_date = Timex.shift(DateTime.to_date(account.opened_at), days: grace_period_days || 0)

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
          due_date: Timex.shift(base_date, months: n),
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

  defp fetch_available_product(_scope, nil), do: {:error, :product_required}

  defp fetch_available_product(scope, product_id) do
    scope
    |> Products.list_available_products()
    |> Enum.find(&(&1.id == product_id))
    |> case do
      nil -> {:error, :product_unavailable}
      product -> {:ok, product}
    end
  end

  defp check_product_bounds(_product, nil, _term_months), do: :ok
  defp check_product_bounds(_product, _amount, nil), do: :ok

  defp check_product_bounds(%LoanProduct{} = product, amount, term_months) do
    cond do
      Decimal.compare(amount, product.minimum_principal) == :lt -> {:error, :amount_below_minimum}
      Decimal.compare(amount, product.maximum_principal) == :gt -> {:error, :amount_above_maximum}
      term_months < product.minimum_term_months -> {:error, :term_below_minimum}
      term_months > product.maximum_term_months -> {:error, :term_above_maximum}
      true -> :ok
    end
  end

  defp to_decimal(%Decimal{} = value), do: value
  defp to_decimal(nil), do: nil

  defp to_decimal(value) do
    case Decimal.cast(value) do
      {:ok, decimal} -> decimal
      :error -> nil
    end
  end

  defp to_integer(value) when is_integer(value), do: value
  defp to_integer(nil), do: nil

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
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
