defmodule MiwayCreditCore.CollectionsTest do
  use MiwayCreditCore.DataCase, async: true

  import MiwayCreditCore.LoansFixtures
  import MiwayCreditCore.AccountsFixtures
  import MiwayCreditCore.OrganisationsFixtures
  alias MiwayCreditCore.{Repo, Collections, Lending, Accounting}
  alias MiwayCreditCore.Accounts.Scope

  describe "classify_arrears/1" do
    test "buckets by days past due" do
      assert Collections.classify_arrears(0) == "current"
      assert Collections.classify_arrears(1) == "1_30_days"
      assert Collections.classify_arrears(30) == "1_30_days"
      assert Collections.classify_arrears(31) == "31_60_days"
      assert Collections.classify_arrears(60) == "31_60_days"
      assert Collections.classify_arrears(61) == "61_90_days"
      assert Collections.classify_arrears(90) == "61_90_days"
      assert Collections.classify_arrears(91) == "over_90_days"
      assert Collections.classify_arrears(365) == "over_90_days"
    end
  end

  describe "case auto-open on overdue" do
    test "mark_overdue_installments/0 opens exactly one case for a newly-overdue account" do
      application = approved_application_fixture(%{"requested_term_months" => "1"})
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      [installment] = Lending.list_installments_for_account(scope, account.id)

      installment |> Ecto.Changeset.change(due_date: Date.add(Date.utc_today(), -1)) |> Repo.update!()
      Lending.mark_overdue_installments()

      cases = Collections.list_cases_for_account(scope, account.id)
      assert [collection_case] = cases
      assert collection_case.status == "open"
      assert collection_case.recovery_status == "none"
      assert collection_case.customer_id == account.customer_id
    end

    test "a second overdue sweep doesn't open a second case" do
      application = approved_application_fixture(%{"requested_term_months" => "2"})
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      [first, second] = Lending.list_installments_for_account(scope, account.id)

      first |> Ecto.Changeset.change(due_date: Date.add(Date.utc_today(), -5)) |> Repo.update!()
      Lending.mark_overdue_installments()
      assert length(Collections.list_cases_for_account(scope, account.id)) == 1

      second |> Ecto.Changeset.change(due_date: Date.add(Date.utc_today(), -1)) |> Repo.update!()
      Lending.mark_overdue_installments()
      assert length(Collections.list_cases_for_account(scope, account.id)) == 1
    end
  end

  describe "case lifecycle" do
    test "escalate_case/1 and close_case/2" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      {:ok, collection_case} = Collections.ensure_case_opened(account)

      assert {:ok, escalated} = Collections.escalate_case(collection_case)
      assert escalated.status == "escalated"

      assert {:ok, closed} = Collections.close_case(escalated, "Account brought current")
      assert closed.status == "closed"
      assert closed.close_reason == "Account brought current"
      assert closed.closed_at

      refute Collections.get_open_case_for_account(scope, account.id)
    end

    test "set_recovery_status/3 to legal_action flips the account to defaulted" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      admin = admin_fixture()
      {:ok, collection_case} = Collections.ensure_case_opened(account)

      assert {:ok, updated} = Collections.set_recovery_status(collection_case, "legal_action", admin.id)
      assert updated.recovery_status == "legal_action"

      reloaded_account = Lending.get_account!(scope, account.id)
      assert reloaded_account.status == "defaulted"
    end

    test "set_recovery_status/3 to in_recovery does not touch the account status" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      admin = admin_fixture()
      {:ok, collection_case} = Collections.ensure_case_opened(account)

      {:ok, _} = Collections.set_recovery_status(collection_case, "in_recovery", admin.id)

      reloaded_account = Lending.get_account!(scope, account.id)
      assert reloaded_account.status == "active"
    end
  end

  describe "log_activity/2 and record_promise/2" do
    test "logs communication history against a case" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      admin = admin_fixture()
      {:ok, collection_case} = Collections.ensure_case_opened(account)

      assert {:ok, activity} =
               Collections.log_activity(collection_case, %{
                 "activity_type" => "call",
                 "outcome" => "reached",
                 "notes" => "Customer says they'll pay Friday",
                 "occurred_at" => DateTime.utc_now() |> DateTime.truncate(:second),
                 "recorded_by_id" => admin.id
               })

      assert [logged] = Collections.list_activities_for_case(scope, collection_case.id)
      assert logged.id == activity.id
      assert logged.activity_type == "call"
    end

    test "records a promise to pay" do
      application = approved_application_fixture()
      account = application.loan_account
      admin = admin_fixture()
      {:ok, collection_case} = Collections.ensure_case_opened(account)

      assert {:ok, promise} =
               Collections.record_promise(collection_case, %{
                 "promised_amount" => "100.00",
                 "promised_date" => Date.add(Date.utc_today(), 5),
                 "recorded_by_id" => admin.id
               })

      assert promise.status == "pending"
    end
  end

  describe "evaluate_promises/0" do
    test "marks a promise kept once a matching payment posts before the promised_date passes" do
      application = approved_application_fixture()
      account = application.loan_account
      admin = admin_fixture()
      {:ok, collection_case} = Collections.ensure_case_opened(account)

      {:ok, promise} =
        Collections.record_promise(collection_case, %{
          "promised_amount" => "40.00",
          "promised_date" => Date.add(Date.utc_today(), -1),
          "recorded_by_id" => admin.id
        })

      payment_fixture(account, %{"amount" => "50.00"})

      assert Collections.evaluate_promises() == 1
      reloaded = Repo.get!(MiwayCreditCore.Collections.PromiseToPay, promise.id)
      assert reloaded.status == "kept"
      assert reloaded.evaluated_at
    end

    test "marks a promise broken once its date passes with no matching payment" do
      application = approved_application_fixture()
      account = application.loan_account
      admin = admin_fixture()
      {:ok, collection_case} = Collections.ensure_case_opened(account)

      {:ok, promise} =
        Collections.record_promise(collection_case, %{
          "promised_amount" => "500.00",
          "promised_date" => Date.add(Date.utc_today(), -1),
          "recorded_by_id" => admin.id
        })

      assert Collections.evaluate_promises() == 1
      reloaded = Repo.get!(MiwayCreditCore.Collections.PromiseToPay, promise.id)
      assert reloaded.status == "broken"
    end

    test "leaves a promise not yet due alone" do
      application = approved_application_fixture()
      account = application.loan_account
      admin = admin_fixture()
      {:ok, collection_case} = Collections.ensure_case_opened(account)

      {:ok, _promise} =
        Collections.record_promise(collection_case, %{
          "promised_amount" => "50.00",
          "promised_date" => Date.add(Date.utc_today(), 5),
          "recorded_by_id" => admin.id
        })

      assert Collections.evaluate_promises() == 0
    end
  end

  describe "restructuring" do
    test "approve_restructuring/2 refuses when the approver is the requester" do
      application = approved_application_fixture()
      account = application.loan_account
      admin = admin_fixture()

      {:ok, request} =
        Collections.request_restructuring(account, %{
          "additional_term_months" => 3,
          "reason" => "Reduced income",
          "requested_by_id" => admin.id
        })

      assert {:error, :maker_checker_violation} = Collections.approve_restructuring(request, admin.id)
    end

    test "approve_restructuring/2 marks remaining installments restructured, leaves paid ones untouched, and generates a schedule covering the true remaining principal" do
      application = approved_application_fixture(%{"requested_term_months" => "3"})
      organisation = MiwayCreditCore.Organisations.get_organisation!(application.organisation_id)
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      requester = admin_fixture()
      approver = staff_member_in_organisation_fixture(organisation, "organisation_administrator")

      [first, second, third] = Lending.list_installments_for_account(scope, account.id)
      payment_fixture(account, %{"amount" => first.scheduled_amount})

      {:ok, request} =
        Collections.request_restructuring(account, %{
          "additional_term_months" => 2,
          "reason" => "Reduced income",
          "requested_by_id" => requester.id
        })

      assert {:ok, approved} = Collections.approve_restructuring(request, approver.id)
      assert approved.status == "approved"

      reloaded_first = Lending.get_installment!(scope, first.id)
      reloaded_second = Lending.get_installment!(scope, second.id)
      reloaded_third = Lending.get_installment!(scope, third.id)
      assert reloaded_first.status == "paid"
      assert reloaded_second.status == "restructured"
      assert reloaded_third.status == "restructured"

      all_installments = Lending.list_installments_for_account(scope, account.id)
      new_installments = Enum.filter(all_installments, &(&1.status == "upcoming"))
      # 2 remaining installments + 2 additional months = 4 new installments
      assert length(new_installments) == 4

      new_principal_total = new_installments |> Enum.map(& &1.scheduled_principal) |> Enum.reduce(&Decimal.add/2)
      old_remaining_principal = Decimal.add(reloaded_second.scheduled_principal, reloaded_third.scheduled_principal)
      assert Decimal.equal?(Decimal.round(new_principal_total, 2), Decimal.round(old_remaining_principal, 2))

      assert Accounting.trial_balance(scope).balanced?
    end
  end

  describe "write-off requests" do
    test "approve_write_off/2 refuses when the approver is the requester" do
      application = approved_application_fixture()
      account = application.loan_account
      admin = admin_fixture()

      {:ok, request} = Collections.request_write_off(account, %{"reason" => "Uncollectable", "requested_by_id" => admin.id})

      assert {:error, :maker_checker_violation} = Collections.approve_write_off(request, admin.id)
    end

    test "approve_write_off/2 calls through to write_off_account/2 and actually zeroes the balance" do
      application = approved_application_fixture()
      organisation = MiwayCreditCore.Organisations.get_organisation!(application.organisation_id)
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      requester = admin_fixture()
      approver = staff_member_in_organisation_fixture(organisation, "organisation_administrator")

      {:ok, request} = Collections.request_write_off(account, %{"reason" => "Uncollectable", "requested_by_id" => requester.id})
      assert Decimal.equal?(request.requested_amount, account.outstanding_balance)

      assert {:ok, approved} = Collections.approve_write_off(request, approver.id)
      assert approved.status == "approved"

      reloaded = Lending.get_account!(scope, account.id)
      assert reloaded.status == "written_off"
      assert Decimal.equal?(reloaded.outstanding_balance, Decimal.new("0.00"))
    end

    test "reject_write_off/3 leaves the account untouched" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      admin = admin_fixture()

      {:ok, request} = Collections.request_write_off(account, %{"reason" => "Uncollectable", "requested_by_id" => admin.id})
      assert {:ok, rejected} = Collections.reject_write_off(request, admin.id, "Customer is paying")
      assert rejected.status == "rejected"

      reloaded = Lending.get_account!(scope, account.id)
      assert reloaded.status == "active"
    end
  end
end
