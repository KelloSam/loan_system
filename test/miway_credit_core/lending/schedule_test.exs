defmodule MiwayCreditCore.Lending.ScheduleTest do
  use MiwayCreditCore.DataCase, async: true

  import MiwayCreditCore.LoansFixtures
  import MiwayCreditCore.CustomersFixtures
  import MiwayCreditCore.OrganisationsFixtures
  alias MiwayCreditCore.{Lending, Accounting}
  alias MiwayCreditCore.Accounts.Scope

  describe "mark_overdue_installments/0" do
    test "flips unpaid installments past their due_date to overdue" do
      application = approved_application_fixture(%{"requested_term_months" => "1"})
      scope = %Scope{organisation_id: application.organisation_id}
      [installment] = Lending.list_installments_for_account(scope, application.loan_account.id)

      installment
      |> Ecto.Changeset.change(due_date: Date.add(Date.utc_today(), -1))
      |> MiwayCreditCore.Repo.update!()

      assert Lending.mark_overdue_installments() == 1
      assert Lending.get_installment!(scope, installment.id).status == "overdue"
    end

    test "leaves installments due today or in the future alone" do
      application = approved_application_fixture(%{"requested_term_months" => "1"})
      scope = %Scope{organisation_id: application.organisation_id}
      [installment] = Lending.list_installments_for_account(scope, application.loan_account.id)

      installment
      |> Ecto.Changeset.change(due_date: Date.utc_today())
      |> MiwayCreditCore.Repo.update!()

      assert Lending.mark_overdue_installments() == 0
      assert Lending.get_installment!(scope, installment.id).status == "upcoming"
    end

    test "does not touch already-paid installments" do
      application = approved_application_fixture(%{"requested_term_months" => "1"})
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      [installment] = Lending.list_installments_for_account(scope, account.id)
      payment_fixture(account, %{"amount" => account.outstanding_balance})

      installment = Lending.get_installment!(scope, installment.id)
      assert installment.status == "paid"

      installment
      |> Ecto.Changeset.change(due_date: Date.add(Date.utc_today(), -30))
      |> MiwayCreditCore.Repo.update!()

      assert Lending.mark_overdue_installments() == 0
      assert Lending.get_installment!(scope, installment.id).status == "paid"
    end

    test "accrues a late payment penalty and posts a penalty ledger entry" do
      application = approved_application_fixture(%{"requested_term_months" => "1"})
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      [installment] = Lending.list_installments_for_account(scope, account.id)

      product = MiwayCreditCore.Products.get_product!(scope, account.loan_product_id)

      {:ok, product} =
        MiwayCreditCore.Products.update_product(product, %{
          "late_payment_penalty_percent" => "10.00"
        })

      installment
      |> Ecto.Changeset.change(due_date: Date.add(Date.utc_today(), -1))
      |> MiwayCreditCore.Repo.update!()

      assert Lending.mark_overdue_installments() == 1

      reloaded_installment = Lending.get_installment!(scope, installment.id)

      expected_penalty =
        installment.scheduled_amount
        |> Decimal.mult(product.late_payment_penalty_percent)
        |> Decimal.div(Decimal.new("100"))
        |> Decimal.round(2)

      assert Decimal.equal?(reloaded_installment.penalty_amount, expected_penalty)

      reloaded_account = Lending.get_account!(scope, account.id)

      assert Decimal.equal?(
               reloaded_account.outstanding_balance,
               Decimal.add(account.outstanding_balance, expected_penalty)
             )

      entries = MiwayCreditCore.Accounting.list_entries_for_account(scope, account.id)
      penalty_entry = Enum.find(entries, &(&1.entry_type == "penalty"))
      assert penalty_entry
      assert Decimal.equal?(penalty_entry.amount, expected_penalty)
      assert Accounting.trial_balance(scope).balanced?
    end

    test "zero-penalty products post no penalty entry" do
      application = approved_application_fixture(%{"requested_term_months" => "1"})
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      [installment] = Lending.list_installments_for_account(scope, account.id)

      installment
      |> Ecto.Changeset.change(due_date: Date.add(Date.utc_today(), -1))
      |> MiwayCreditCore.Repo.update!()

      assert Lending.mark_overdue_installments() == 1

      reloaded_account = Lending.get_account!(scope, account.id)
      assert Decimal.equal?(reloaded_account.outstanding_balance, account.outstanding_balance)

      refute Enum.any?(
               MiwayCreditCore.Accounting.list_entries_for_account(scope, account.id),
               &(&1.entry_type == "penalty")
             )
    end
  end

  describe "days_past_due/1" do
    test "0 when nothing is overdue" do
      application = approved_application_fixture(%{"requested_term_months" => "1"})
      assert Lending.days_past_due(application.loan_account) == 0
    end

    test "days since the oldest overdue installment fell due" do
      application = approved_application_fixture(%{"requested_term_months" => "1"})
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      [installment] = Lending.list_installments_for_account(scope, account.id)

      installment
      |> Ecto.Changeset.change(due_date: Date.add(Date.utc_today(), -5))
      |> MiwayCreditCore.Repo.update!()

      Lending.mark_overdue_installments()

      assert Lending.days_past_due(Lending.get_account!(scope, account.id)) == 5
    end
  end

  describe "count_overdue_installments/2 and total_overdue_amount/2" do
    test "counts and totals overdue installments across an organisation, optionally scoped to a customer" do
      organisation = organisation_fixture()
      customer1 = customer_fixture_in_organisation(organisation)
      customer2 = customer_fixture_in_organisation(organisation)
      scope = %Scope{organisation_id: organisation.id}

      app1 =
        approved_application_fixture(%{
          "customer_id" => customer1.id,
          "requested_term_months" => "1"
        })

      app2 =
        approved_application_fixture(%{
          "customer_id" => customer2.id,
          "requested_term_months" => "1"
        })

      for app <- [app1, app2] do
        [installment] = Lending.list_installments_for_account(scope, app.loan_account.id)

        installment
        |> Ecto.Changeset.change(due_date: Date.add(Date.utc_today(), -5))
        |> MiwayCreditCore.Repo.update!()
      end

      Lending.mark_overdue_installments()

      assert Lending.count_overdue_installments(scope) == 2
      assert Lending.count_overdue_installments(scope, app1.customer_id) == 1

      [installment] = Lending.list_installments_for_account(scope, app1.loan_account.id)

      assert Decimal.equal?(
               Lending.total_overdue_amount(scope, app1.customer_id),
               installment.scheduled_amount
             )
    end

    test "zero when there is no overdue installment" do
      organisation = organisation_fixture()
      scope = %Scope{organisation_id: organisation.id}
      assert Lending.count_overdue_installments(scope) == 0
      assert Decimal.equal?(Lending.total_overdue_amount(scope), Decimal.new("0.00"))
    end
  end

  describe "get_upcoming_installments/2" do
    test "only returns unpaid, future-or-overdue installments for the customer, oldest first" do
      application = approved_application_fixture(%{"requested_term_months" => "3"})
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account

      results = Lending.get_upcoming_installments(scope, application.customer_id)
      assert length(results) == 3
      assert Enum.all?(results, &(&1.loan_account.id == account.id))

      assert results |> Enum.map(& &1.due_date) ==
               Enum.sort(Enum.map(results, & &1.due_date), Date)
    end
  end
end
