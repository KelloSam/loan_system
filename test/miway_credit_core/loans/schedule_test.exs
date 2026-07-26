defmodule MiwayCreditCore.Loans.ScheduleTest do
  use MiwayCreditCore.DataCase, async: true

  import MiwayCreditCore.LoansFixtures
  alias MiwayCreditCore.Loans

  describe "mark_overdue_installments/0" do
    test "flips unpaid installments past their due_date to overdue" do
      application = approved_application_fixture(%{"requested_term_months" => "1"})
      [installment] = Loans.list_installments_for_account(application.loan_account.id)

      installment
      |> Ecto.Changeset.change(due_date: Date.add(Date.utc_today(), -1))
      |> MiwayCreditCore.Repo.update!()

      assert Loans.mark_overdue_installments() == 1
      assert Loans.get_installment!(installment.id).status == "overdue"
    end

    test "leaves installments due today or in the future alone" do
      application = approved_application_fixture(%{"requested_term_months" => "1"})
      [installment] = Loans.list_installments_for_account(application.loan_account.id)

      installment
      |> Ecto.Changeset.change(due_date: Date.utc_today())
      |> MiwayCreditCore.Repo.update!()

      assert Loans.mark_overdue_installments() == 0
      assert Loans.get_installment!(installment.id).status == "upcoming"
    end

    test "does not touch already-paid installments" do
      application = approved_application_fixture(%{"requested_term_months" => "1"})
      account = application.loan_account
      [installment] = Loans.list_installments_for_account(account.id)
      payment_fixture(account, %{"amount" => account.outstanding_balance})

      installment = Loans.get_installment!(installment.id)
      assert installment.status == "paid"

      installment |> Ecto.Changeset.change(due_date: Date.add(Date.utc_today(), -30)) |> MiwayCreditCore.Repo.update!()
      assert Loans.mark_overdue_installments() == 0
      assert Loans.get_installment!(installment.id).status == "paid"
    end
  end

  describe "count_overdue_installments/1 and total_overdue_amount/1" do
    test "counts and totals overdue installments, optionally scoped to a customer" do
      app1 = approved_application_fixture(%{"requested_term_months" => "1"})
      app2 = approved_application_fixture(%{"requested_term_months" => "1"})

      for app <- [app1, app2] do
        [installment] = Loans.list_installments_for_account(app.loan_account.id)
        installment |> Ecto.Changeset.change(due_date: Date.add(Date.utc_today(), -5)) |> MiwayCreditCore.Repo.update!()
      end

      Loans.mark_overdue_installments()

      assert Loans.count_overdue_installments() == 2
      assert Loans.count_overdue_installments(app1.customer_id) == 1

      [installment] = Loans.list_installments_for_account(app1.loan_account.id)
      assert Decimal.equal?(Loans.total_overdue_amount(app1.customer_id), installment.scheduled_amount)
    end

    test "zero when there is no overdue installment" do
      assert Loans.count_overdue_installments() == 0
      assert Decimal.equal?(Loans.total_overdue_amount(), Decimal.new("0.00"))
    end
  end

  describe "get_upcoming_installments/1" do
    test "only returns unpaid, future-or-overdue installments for the customer, oldest first" do
      application = approved_application_fixture(%{"requested_term_months" => "3"})
      account = application.loan_account

      results = Loans.get_upcoming_installments(application.customer_id)
      assert length(results) == 3
      assert Enum.all?(results, &(&1.loan_account.id == account.id))
      assert results |> Enum.map(& &1.due_date) == Enum.sort(Enum.map(results, & &1.due_date), Date)
    end
  end
end
