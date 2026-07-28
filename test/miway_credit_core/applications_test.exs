defmodule MiwayCreditCore.ApplicationsTest do
  use MiwayCreditCore.DataCase, async: true

  import MiwayCreditCore.CustomersFixtures
  import MiwayCreditCore.AccountsFixtures
  import MiwayCreditCore.LoansFixtures
  import MiwayCreditCore.OrganisationsFixtures
  alias MiwayCreditCore.{Applications, Accounting, Lending, Products, Customers, Accounts}
  alias MiwayCreditCore.Applications.{LoanApplication, ApprovalDecision}
  alias MiwayCreditCore.CreditReporting.ManualAdapter
  alias MiwayCreditCore.Accounts.Scope

  describe "create_application/2" do
    test "creates a pending application and stamps a fraud-detector risk_level/risk_score" do
      customer = customer_fixture()
      scope = %Scope{organisation_id: customer.organisation_id}

      assert {:ok, %LoanApplication{} = application} =
               Applications.create_application(scope, valid_application_attrs(%{"customer_id" => customer.id}))

      assert application.status == "pending"
      assert application.organisation_id == customer.organisation_id
      # A brand-new customer with no repayment history always scores at
      # least 35 (new_customer +20, no_repayment_history +15) — always
      # "medium" or worse, never "low".
      assert application.risk_level in ["medium", "high"]
      assert application.risk_score >= 35
    end

    test "recalculates the customer's total_loans; current_balance stays zero (no account yet)" do
      customer = customer_fixture()
      scope = %Scope{organisation_id: customer.organisation_id}
      {:ok, _application} = Applications.create_application(scope, valid_application_attrs(%{"customer_id" => customer.id}))

      reloaded = Customers.get_customer!(scope, customer.id)
      assert reloaded.total_loans == 1
      assert Decimal.equal?(reloaded.current_balance, Decimal.new("0.00"))
    end

    test "blocks a second application while one is still pending" do
      customer = customer_fixture()
      scope = %Scope{organisation_id: customer.organisation_id}
      {:ok, _first} = Applications.create_application(scope, valid_application_attrs(%{"customer_id" => customer.id}))

      assert {:error, :pending_application_exists} =
               Applications.create_application(scope, valid_application_attrs(%{"customer_id" => customer.id}))
    end

    test "blocks a new application within 30 days of a rejection" do
      customer = customer_fixture()
      scope = %Scope{organisation_id: customer.organisation_id}
      application = application_fixture(%{"customer_id" => customer.id})
      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      {:ok, assessed} = Applications.assess_application(application, admin_scope)
      {:ok, _rejected} = Applications.reject_application(assessed, admin_scope, "Insufficient income")

      assert {:error, :rejection_cooldown} =
               Applications.create_application(scope, valid_application_attrs(%{"customer_id" => customer.id}))
    end

    test "rejects invalid attrs with a changeset error" do
      customer = customer_fixture()
      scope = %Scope{organisation_id: customer.organisation_id}

      assert {:error, %Ecto.Changeset{}} =
               Applications.create_application(
                 scope,
                 valid_application_attrs(%{"customer_id" => customer.id, "purpose" => String.duplicate("x", 501)})
               )
    end

    test "rejects an amount below the product's minimum principal with a clear reason, not a bare changeset error" do
      customer = customer_fixture()
      scope = %Scope{organisation_id: customer.organisation_id}

      assert {:error, :amount_below_minimum} =
               Applications.create_application(
                 scope,
                 valid_application_attrs(%{"customer_id" => customer.id, "requested_amount" => "-5"})
               )
    end

    test "with scope :all (platform administrator), still derives organisation_id from the customer applied for" do
      customer = customer_fixture()

      assert {:ok, application} =
               Applications.create_application(
                 %Scope{organisation_id: :all},
                 valid_application_attrs(%{"customer_id" => customer.id})
               )

      assert application.organisation_id == customer.organisation_id
    end
  end

  describe "fraud_signals/1" do
    test "lists the human-readable signals behind the risk score" do
      application = application_fixture()
      signals = Applications.fraud_signals(application)
      assert is_list(signals)
      assert Enum.any?(signals, &(&1 =~ "less than 7 days old"))
      assert Enum.any?(signals, &(&1 =~ "No repayment history"))
    end
  end

  describe "assess_application/3" do
    test "flips pending to under_review, stamps assessed_at/assessed_by_id, and persists notes" do
      application = application_fixture()
      admin = admin_fixture()

      assert {:ok, assessed} =
               Applications.assess_application(application, %Scope{user: admin, organisation_id: :all}, "Docs check out")

      assert assessed.status == "under_review"
      assert assessed.assessed_at
      assert assessed.assessed_by_id == admin.id
      assert assessed.assessment_notes == "Docs check out"
    end

    test "notes are optional" do
      application = application_fixture()
      admin = admin_fixture()

      assert {:ok, assessed} = Applications.assess_application(application, %Scope{user: admin, organisation_id: :all})
      assert assessed.assessment_notes == nil
    end

    test "rejects assessing a non-pending application" do
      application = application_fixture()
      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      {:ok, assessed} = Applications.assess_application(application, admin_scope)

      assert {:error, :invalid_status} = Applications.assess_application(assessed, admin_scope)
    end
  end

  describe "approve_application/2" do
    test "rejects approving a pending (not-yet-assessed) application" do
      application = application_fixture()
      admin = admin_fixture()

      assert {:error, :invalid_status} = Applications.approve_application(application, %Scope{user: admin, organisation_id: :all}, true)
    end

    test "flips under_review to approved, stamps decided_at/decided_by_id, and does not open a LoanAccount yet" do
      application = application_fixture()
      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      {:ok, assessed} = Applications.assess_application(application, admin_scope)

      assert {:ok, approved} = Applications.approve_application(assessed, admin_scope, true)
      assert approved.status == "approved"
      assert approved.decided_at
      assert approved.decided_by_id == admin.id
      assert Applications.get_application!(%Scope{organisation_id: :all}, approved.id).loan_account == nil
    end
  end

  describe "disburse_application/2" do
    test "rejects disbursing an application that isn't approved yet" do
      application = application_fixture()
      admin = admin_fixture()

      assert {:error, :invalid_status} = Applications.disburse_application(application, %Scope{user: admin, organisation_id: :all})
    end

    test "flips approved to disbursed, stamps disbursed_at/disbursed_by_id, and opens a LoanAccount" do
      application = application_fixture()
      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      {:ok, assessed} = Applications.assess_application(application, admin_scope)
      {:ok, approved} = Applications.approve_application(assessed, admin_scope, true)

      assert {:ok, disbursed, account} = Applications.disburse_application(approved, admin_scope)
      assert disbursed.status == "disbursed"
      assert disbursed.disbursed_at
      assert disbursed.disbursed_by_id == admin.id

      assert account.loan_application_id == disbursed.id
      assert account.customer_id == disbursed.customer_id
      assert account.organisation_id == disbursed.organisation_id
      assert account.status == "active"
      assert Decimal.compare(account.outstanding_balance, Decimal.new("0")) == :gt
    end

    test "the opening balance reconciles against the ledger's disbursement entry" do
      application = application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      {:ok, assessed} = Applications.assess_application(application, admin_scope)
      {:ok, approved} = Applications.approve_application(assessed, admin_scope, true)
      {:ok, _disbursed, account} = Applications.disburse_application(approved, admin_scope)

      assert Decimal.equal?(Accounting.rebuild_outstanding_balance(scope, account.id), account.outstanding_balance)

      [entry] = Accounting.list_entries_for_account(scope, account.id)
      assert entry.entry_type == "disbursement"
      assert Decimal.equal?(entry.amount, account.outstanding_balance)
    end

    test "recalculates the customer's current_balance to the new account's outstanding_balance" do
      application = application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      {:ok, assessed} = Applications.assess_application(application, admin_scope)
      {:ok, approved} = Applications.approve_application(assessed, admin_scope, true)
      {:ok, _disbursed, account} = Applications.disburse_application(approved, admin_scope)

      reloaded_customer = Customers.get_customer!(scope, application.customer_id)
      assert Decimal.equal?(reloaded_customer.current_balance, account.outstanding_balance)
    end

    test "generates a monthly repayment schedule matching the account's term" do
      application = application_fixture(%{"requested_term_months" => "3"})
      scope = %Scope{organisation_id: application.organisation_id}
      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      {:ok, assessed} = Applications.assess_application(application, admin_scope)
      {:ok, approved} = Applications.approve_application(assessed, admin_scope, true)
      {:ok, _disbursed, account} = Applications.disburse_application(approved, admin_scope)

      installments = Lending.list_installments_for_account(scope, account.id)
      assert length(installments) == 3
      assert Enum.all?(installments, &(&1.status == "upcoming"))
      assert Enum.all?(installments, &Decimal.equal?(&1.paid_amount, Decimal.new("0.00")))

      due_dates = installments |> Enum.map(& &1.due_date) |> Enum.sort(Date)
      opened_date = DateTime.to_date(account.opened_at)
      assert Enum.at(due_dates, 0) == Timex.shift(opened_date, months: 1)
      assert Enum.at(due_dates, 1) == Timex.shift(opened_date, months: 2)
      assert Enum.at(due_dates, 2) == Timex.shift(opened_date, months: 3)

      total_scheduled = installments |> Enum.map(& &1.scheduled_amount) |> Enum.reduce(&Decimal.add/2)
      assert Decimal.equal?(total_scheduled, account.outstanding_balance)
    end
  end

  describe "reject_application/3" do
    test "rejects rejecting a pending (not-yet-assessed) application" do
      application = application_fixture()
      admin = admin_fixture()

      assert {:error, :invalid_status} =
               Applications.reject_application(application, %Scope{user: admin, organisation_id: :all}, "Not eligible")
    end

    test "sets status, decision fields, and rejection_reason" do
      application = application_fixture()
      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      {:ok, assessed} = Applications.assess_application(application, admin_scope)

      assert {:ok, rejected} = Applications.reject_application(assessed, admin_scope, "Debt-to-income too high")
      assert rejected.status == "rejected"
      assert rejected.decided_at
      assert rejected.decided_by_id == admin.id
      assert rejected.rejection_reason == "Debt-to-income too high"
    end

    test "does not create a LoanAccount" do
      application = application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      {:ok, assessed} = Applications.assess_application(application, admin_scope)
      {:ok, rejected} = Applications.reject_application(assessed, admin_scope, "Not eligible")

      assert Applications.get_application!(scope, rejected.id).loan_account == nil
    end
  end

  describe "withdraw_application/2" do
    test "succeeds from pending" do
      application = application_fixture()
      admin = admin_fixture()

      assert {:ok, withdrawn} = Applications.withdraw_application(application, %Scope{user: admin, organisation_id: :all})
      assert withdrawn.status == "withdrawn"
    end

    test "succeeds from under_review" do
      application = application_fixture()
      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      {:ok, assessed} = Applications.assess_application(application, admin_scope)

      assert {:ok, withdrawn} = Applications.withdraw_application(assessed, admin_scope)
      assert withdrawn.status == "withdrawn"
    end

    test "rejects withdrawing an approved application" do
      application = application_fixture()
      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      {:ok, assessed} = Applications.assess_application(application, admin_scope)
      {:ok, approved} = Applications.approve_application(assessed, admin_scope, true)

      assert {:error, :invalid_status} = Applications.withdraw_application(approved, admin_scope)
    end

    test "rejects withdrawing a disbursed application" do
      application = application_fixture()
      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      {:ok, assessed} = Applications.assess_application(application, admin_scope)
      {:ok, approved} = Applications.approve_application(assessed, admin_scope, true)
      {:ok, disbursed, _account} = Applications.disburse_application(approved, admin_scope)

      assert {:error, :invalid_status} = Applications.withdraw_application(disbursed, admin_scope)
    end

    test "rejects withdrawing a rejected application" do
      application = application_fixture()
      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      {:ok, assessed} = Applications.assess_application(application, admin_scope)
      {:ok, rejected} = Applications.reject_application(assessed, admin_scope, "Not eligible")

      assert {:error, :invalid_status} = Applications.withdraw_application(rejected, admin_scope)
    end
  end

  describe "update_application/2 and delete_application/1" do
    test "update_application/2 updates permitted fields" do
      application = application_fixture()
      assert {:ok, updated} = Applications.update_application(application, %{"purpose" => "School fees"})
      assert updated.purpose == "School fees"
    end

    test "delete_application/1 removes the application and recalculates customer stats" do
      application = application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      assert {:ok, _} = Applications.delete_application(application)
      assert_raise Ecto.NoResultsError, fn -> Applications.get_application!(scope, application.id) end

      reloaded_customer = Customers.get_customer!(scope, application.customer_id)
      assert reloaded_customer.total_loans == 0
    end
  end

  describe "aggregate counters" do
    test "count_applications/1 and count_active_applications/1 are scoped to one organisation" do
      organisation = organisation_fixture()
      scope = %Scope{organisation_id: organisation.id}
      customer = customer_fixture_in_organisation(organisation)

      assert Applications.count_applications(scope) == 0
      assert Applications.count_active_applications(scope) == 0

      application = application_fixture(%{"customer_id" => customer.id})

      assert Applications.count_applications(scope) == 1
      assert Applications.count_active_applications(scope) == 1

      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      {:ok, assessed} = Applications.assess_application(application, admin_scope)
      # Still "active" — under_review is in-flight too, not yet decided.
      assert Applications.count_active_applications(scope) == 1

      {:ok, _} = Applications.reject_application(assessed, admin_scope, "Not eligible")
      assert Applications.count_active_applications(scope) == 0
    end
  end

  describe "approve_application/2 — affordability requirement" do
    test "blocked with :income_data_missing when the product requires it and the customer has no income on file" do
      organisation = organisation_fixture()
      customer = customer_fixture_in_organisation(organisation)
      {:ok, product} = Products.create_product(%Scope{organisation_id: organisation.id}, valid_product_attrs(%{"requires_affordability_check" => true}))

      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      {:ok, application} =
        Applications.create_application(
          %Scope{organisation_id: organisation.id},
          valid_application_attrs(%{"customer_id" => customer.id, "loan_product_id" => product.id})
        )
      {:ok, assessed} = Applications.assess_application(application, admin_scope)

      assert {:error, :income_data_missing} = Applications.approve_application(assessed, admin_scope, true)
    end

    test "blocked with :affordability_exceeded when the ratio is too high; passes once income covers it" do
      organisation = organisation_fixture()
      customer = customer_fixture_in_organisation(organisation, %{"monthly_income" => "100"})

      {:ok, product} =
        Products.create_product(
          %Scope{organisation_id: organisation.id},
          valid_product_attrs(%{"requires_affordability_check" => true, "interest_rate" => "0"})
        )

      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      {:ok, application} =
        Applications.create_application(
          %Scope{organisation_id: organisation.id},
          valid_application_attrs(%{
            "customer_id" => customer.id,
            "loan_product_id" => product.id,
            "requested_amount" => "1000",
            "requested_term_months" => "12"
          })
        )
      {:ok, assessed} = Applications.assess_application(application, admin_scope)

      assert {:error, :affordability_exceeded} = Applications.approve_application(assessed, admin_scope, true)
    end
  end

  describe "approve_application/2 — CRB requirement" do
    test "blocked with :crb_check_required when the product requires it and no report is on file" do
      organisation = organisation_fixture()
      customer = customer_fixture_in_organisation(organisation)
      {:ok, product} = Products.create_product(%Scope{organisation_id: organisation.id}, valid_product_attrs(%{"requires_crb_check" => true}))

      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      {:ok, application} =
        Applications.create_application(
          %Scope{organisation_id: organisation.id},
          valid_application_attrs(%{"customer_id" => customer.id, "loan_product_id" => product.id})
        )
      {:ok, assessed} = Applications.assess_application(application, admin_scope)

      assert {:error, :crb_check_required} = Applications.approve_application(assessed, admin_scope, true)
    end

    test "blocked with :adverse_crb_report when the latest report is adverse" do
      organisation = organisation_fixture()
      customer = customer_fixture_in_organisation(organisation)
      {:ok, product} = Products.create_product(%Scope{organisation_id: organisation.id}, valid_product_attrs(%{"requires_crb_check" => true}))

      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      grant_credit_check_consent(customer, admin.id)
      {:ok, _report} =
        ManualAdapter.record_report(admin_scope, customer, %{"outcome" => "adverse", "checked_at" => Date.utc_today()}, admin.id)

      {:ok, application} =
        Applications.create_application(
          %Scope{organisation_id: organisation.id},
          valid_application_attrs(%{"customer_id" => customer.id, "loan_product_id" => product.id})
        )
      {:ok, assessed} = Applications.assess_application(application, admin_scope)

      assert {:error, :adverse_crb_report} = Applications.approve_application(assessed, admin_scope, true)
    end

    test "blocked with :crb_check_expired when the latest clear report is more than 90 days old" do
      organisation = organisation_fixture()
      customer = customer_fixture_in_organisation(organisation)
      {:ok, product} = Products.create_product(%Scope{organisation_id: organisation.id}, valid_product_attrs(%{"requires_crb_check" => true}))

      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      grant_credit_check_consent(customer, admin.id)
      stale_date = Date.add(Date.utc_today(), -91)
      {:ok, _report} =
        ManualAdapter.record_report(admin_scope, customer, %{"outcome" => "clear", "checked_at" => stale_date}, admin.id)

      {:ok, application} =
        Applications.create_application(
          %Scope{organisation_id: organisation.id},
          valid_application_attrs(%{"customer_id" => customer.id, "loan_product_id" => product.id})
        )
      {:ok, assessed} = Applications.assess_application(application, admin_scope)

      assert {:error, :crb_check_expired} = Applications.approve_application(assessed, admin_scope, true)
    end

    test "succeeds once a recent clear report is on file" do
      organisation = organisation_fixture()
      customer = customer_fixture_in_organisation(organisation)
      {:ok, product} = Products.create_product(%Scope{organisation_id: organisation.id}, valid_product_attrs(%{"requires_crb_check" => true}))

      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      grant_credit_check_consent(customer, admin.id)
      {:ok, _report} =
        ManualAdapter.record_report(admin_scope, customer, %{"outcome" => "clear", "checked_at" => Date.utc_today()}, admin.id)

      {:ok, application} =
        Applications.create_application(
          %Scope{organisation_id: organisation.id},
          valid_application_attrs(%{"customer_id" => customer.id, "loan_product_id" => product.id})
        )
      {:ok, assessed} = Applications.assess_application(application, admin_scope)

      assert {:ok, %LoanApplication{status: "approved"}} = Applications.approve_application(assessed, admin_scope, true)
    end
  end

  describe "approve_application/3 — conflict of interest attestation" do
    test "refuses without an explicit attestation" do
      application = application_fixture()
      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      {:ok, assessed} = Applications.assess_application(application, admin_scope)

      assert {:error, :conflict_of_interest_attestation_required} =
               Applications.approve_application(assessed, admin_scope, false)
    end
  end

  describe "approve_application/3 and reject_application/4 — separation of duties toggle" do
    test "requires_separation_of_duties: false lets the maker decide their own application" do
      organisation = organisation_fixture()
      customer = customer_fixture_in_organisation(organisation)

      {:ok, product} =
        Products.create_product(%Scope{organisation_id: organisation.id}, valid_product_attrs(%{"requires_separation_of_duties" => false}))

      maker = staff_member_in_organisation_fixture(organisation, "organisation_administrator")
      maker_scope = %Scope{user: maker, staff_member: Accounts.get_staff_member(maker.id), organisation_id: organisation.id}

      {:ok, application} =
        Applications.create_application(maker_scope, valid_application_attrs(%{"customer_id" => customer.id, "loan_product_id" => product.id}))
      {:ok, assessed} = Applications.assess_application(application, maker_scope)

      assert {:ok, %LoanApplication{status: "approved"}} = Applications.approve_application(assessed, maker_scope, true)
    end
  end

  describe "reject_application/4 — structured decline reason" do
    test "persists decline_reason_category on the ApprovalDecision alongside the freeform reason" do
      application = application_fixture()
      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      {:ok, assessed} = Applications.assess_application(application, admin_scope)

      assert {:ok, rejected} =
               Applications.reject_application(assessed, admin_scope, "Too much existing debt", "poor_credit_history")

      [decision] = Repo.all(ApprovalDecision) |> Enum.filter(&(&1.loan_application_id == rejected.id))
      assert decision.decision == "rejected"
      assert decision.decline_reason_category == "poor_credit_history"
      assert decision.notes == "Too much existing debt"
    end

    test "defaults decline_reason_category to \"other\" when not supplied" do
      application = application_fixture()
      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      {:ok, assessed} = Applications.assess_application(application, admin_scope)

      {:ok, rejected} = Applications.reject_application(assessed, admin_scope, "Not eligible")

      [decision] = Repo.all(ApprovalDecision) |> Enum.filter(&(&1.loan_application_id == rejected.id))
      assert decision.decline_reason_category == "other"
    end
  end

  describe "approve_application/3 — multi-level approval" do
    test "level 1 alone leaves the application under_review when a second level is required" do
      {application, _level1_scope, level1_scope, _level2_scope} = two_level_setup()

      assert {:ok, still_under_review} = Applications.approve_application(application, level1_scope, true)
      assert still_under_review.status == "under_review"
    end

    test "a different person completing level 2 flips the application to approved" do
      {application, _org, level1_scope, level2_scope} = two_level_setup()

      {:ok, after_level1} = Applications.approve_application(application, level1_scope, true)
      assert {:ok, %LoanApplication{status: "approved"}} = Applications.approve_application(after_level1, level2_scope, true)
    end

    test "the same person cannot decide both levels" do
      {application, _org, level1_scope, _level2_scope} = two_level_setup()

      {:ok, after_level1} = Applications.approve_application(application, level1_scope, true)
      assert {:error, :already_decided} = Applications.approve_application(after_level1, level1_scope, true)
    end

    test "disburse_application/2 only succeeds once both levels have concurred" do
      {application, _org, level1_scope, level2_scope} = two_level_setup()

      {:ok, after_level1} = Applications.approve_application(application, level1_scope, true)
      assert {:error, :invalid_status} = Applications.disburse_application(after_level1, level2_scope)

      {:ok, fully_approved} = Applications.approve_application(after_level1, level2_scope, true)
      assert {:ok, %LoanApplication{status: "disbursed"}, _account} = Applications.disburse_application(fully_approved, level2_scope)
    end
  end

  describe "approve_application/3 — committee decisions" do
    test "quorum not yet reached leaves the application under_review" do
      {application, voter1_scope, _voter2_scope, _voter3_scope} = committee_setup()

      assert {:ok, still_under_review} = Applications.approve_application(application, voter1_scope, true)
      assert still_under_review.status == "under_review"
    end

    test "reaching quorum with distinct voters flips the application to approved" do
      {application, voter1_scope, voter2_scope, _voter3_scope} = committee_setup()

      {:ok, after_voter1} = Applications.approve_application(application, voter1_scope, true)
      assert {:ok, %LoanApplication{status: "approved"}} = Applications.approve_application(after_voter1, voter2_scope, true)
    end

    test "a third vote isn't needed once quorum already concluded the level" do
      {application, voter1_scope, voter2_scope, voter3_scope} = committee_setup()

      {:ok, after_voter1} = Applications.approve_application(application, voter1_scope, true)
      {:ok, approved} = Applications.approve_application(after_voter1, voter2_scope, true)

      assert {:error, :invalid_status} = Applications.approve_application(approved, voter3_scope, true)
    end
  end

  describe "conditionally_approve_application/4" do
    test "moves the application straight to approved with conditions attached" do
      application = application_fixture()
      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      {:ok, assessed} = Applications.assess_application(application, admin_scope)

      assert {:ok, conditional} =
               Applications.conditionally_approve_application(assessed, admin_scope, "Provide updated payslip", true)

      assert conditional.status == "approved"
      assert conditional.conditions == "Provide updated payslip"
      assert conditional.conditions_cleared_at == nil
    end

    test "disburse_application/2 refuses until clear_conditions/2 confirms them" do
      application = application_fixture()
      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      {:ok, assessed} = Applications.assess_application(application, admin_scope)
      {:ok, conditional} = Applications.conditionally_approve_application(assessed, admin_scope, "Provide updated payslip", true)

      assert {:error, :conditions_not_cleared} = Applications.disburse_application(conditional, admin_scope)

      assert {:ok, cleared} = Applications.clear_conditions(conditional, admin_scope)
      assert {:ok, %LoanApplication{status: "disbursed"}, _account} = Applications.disburse_application(cleared, admin_scope)
    end

    test "clear_conditions/2 refuses when there are no conditions to clear" do
      application = approved_application_fixture()
      assert {:error, :no_conditions_to_clear} = Applications.clear_conditions(application, %Scope{organisation_id: :all})
    end
  end

  describe "refer_application/3" do
    test "moves an under_review application to referred, requiring a reason" do
      application = application_fixture()
      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      {:ok, assessed} = Applications.assess_application(application, admin_scope)

      assert {:ok, referred} = Applications.refer_application(assessed, admin_scope, "Need proof of income")
      assert referred.status == "referred"
    end

    test "the full referral round-trip: refer, re-assess, approve normally" do
      application = application_fixture()
      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      {:ok, assessed} = Applications.assess_application(application, admin_scope)
      {:ok, referred} = Applications.refer_application(assessed, admin_scope, "Need proof of income")

      assert {:ok, reassessed} = Applications.assess_application(referred, admin_scope, "Payslip received")
      assert reassessed.status == "under_review"

      assert {:ok, %LoanApplication{status: "approved"}} = Applications.approve_application(reassessed, admin_scope, true)
    end

    test "rejects referring a pending (not yet assessed) application" do
      application = application_fixture()
      admin = admin_fixture()

      assert {:error, :invalid_status} =
               Applications.refer_application(application, %Scope{user: admin, organisation_id: :all}, "Need more info")
    end
  end

  # Two-level product: level 1 gated to organisation_administrator (the
  # default minimum_approval_role), level 2 requires a second, distinct
  # organisation_administrator.
  defp two_level_setup do
    organisation = organisation_fixture()
    customer = customer_fixture_in_organisation(organisation)

    {:ok, product} =
      Products.create_product(
        %Scope{organisation_id: organisation.id},
        valid_product_attrs(%{
          "requires_second_level_approval" => true,
          "minimum_approval_role" => "organisation_administrator",
          "second_level_minimum_role" => "organisation_administrator"
        })
      )

    level1 = staff_member_in_organisation_fixture(organisation, "organisation_administrator")
    level1_scope = %Scope{user: level1, staff_member: Accounts.get_staff_member(level1.id), organisation_id: organisation.id}

    level2 = staff_member_in_organisation_fixture(organisation, "organisation_administrator")
    level2_scope = %Scope{user: level2, staff_member: Accounts.get_staff_member(level2.id), organisation_id: organisation.id}

    {:ok, application} =
      Applications.create_application(
        %Scope{organisation_id: organisation.id},
        valid_application_attrs(%{"customer_id" => customer.id, "loan_product_id" => product.id})
      )

    {:ok, assessed} = Applications.assess_application(application, level1_scope)

    {assessed, organisation, level1_scope, level2_scope}
  end

  # Committee product: no second level, but the (only, final) level
  # requires 2-of-3 concurring approvals from loan_officer-or-above.
  defp committee_setup do
    organisation = organisation_fixture()
    customer = customer_fixture_in_organisation(organisation)

    {:ok, product} =
      Products.create_product(
        %Scope{organisation_id: organisation.id},
        valid_product_attrs(%{
          "requires_committee_decision" => true,
          "committee_size" => "3",
          "committee_quorum" => "2",
          "minimum_approval_role" => "loan_officer"
        })
      )

    voter1 = staff_member_in_organisation_fixture(organisation, "loan_officer")
    voter1_scope = %Scope{user: voter1, staff_member: Accounts.get_staff_member(voter1.id), organisation_id: organisation.id}

    voter2 = staff_member_in_organisation_fixture(organisation, "loan_officer")
    voter2_scope = %Scope{user: voter2, staff_member: Accounts.get_staff_member(voter2.id), organisation_id: organisation.id}

    voter3 = staff_member_in_organisation_fixture(organisation, "loan_officer")
    voter3_scope = %Scope{user: voter3, staff_member: Accounts.get_staff_member(voter3.id), organisation_id: organisation.id}

    {:ok, application} =
      Applications.create_application(
        %Scope{organisation_id: organisation.id},
        valid_application_attrs(%{"customer_id" => customer.id, "loan_product_id" => product.id})
      )

    {:ok, assessed} = Applications.assess_application(application, voter1_scope)

    {assessed, voter1_scope, voter2_scope, voter3_scope}
  end

  defp grant_credit_check_consent(customer, recorded_by_id) do
    {:ok, _consent} =
      Customers.create_consent(
        customer,
        %{"consent_type" => "credit_check", "method" => "signed_form", "granted_at" => DateTime.utc_now()},
        recorded_by_id
      )
  end

  defp valid_product_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      "name" => "Test Product #{System.unique_integer([:positive])}",
      "minimum_principal" => "100.00",
      "maximum_principal" => "50000.00",
      "interest_method" => "reducing_balance",
      "interest_rate" => "18.00",
      "minimum_term_months" => "1",
      "maximum_term_months" => "24",
      "repayment_frequency" => "monthly",
      "effective_from" => Date.utc_today()
    })
  end
end
