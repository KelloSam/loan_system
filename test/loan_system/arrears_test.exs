defmodule LoanSystem.ArrearsTest do
  use LoanSystem.DataCase, async: true

  import LoanSystem.LoansFixtures
  alias LoanSystem.{Loans, Repo}
  alias LoanSystem.Loans.Payment

  describe "mark_overdue_payments/0" do
    test "flips pending installments past their due_date to overdue" do
      loan = approved_loan_fixture(%{"term_months" => "1"})
      [installment] = Loans.list_payments_for_loan(loan.id)

      # Backdate it, as if its due date already passed.
      installment
      |> Ecto.Changeset.change(due_date: Date.add(Date.utc_today(), -1))
      |> Repo.update!()

      assert Loans.mark_overdue_payments() == 1

      reloaded = Loans.get_payment!(installment.id)
      assert reloaded.status == "overdue"
    end

    test "leaves pending installments due today or in the future alone" do
      loan = approved_loan_fixture(%{"term_months" => "1"})
      [installment] = Loans.list_payments_for_loan(loan.id)

      installment
      |> Ecto.Changeset.change(due_date: Date.utc_today())
      |> Repo.update!()

      assert Loans.mark_overdue_payments() == 0
      assert Loans.get_payment!(installment.id).status == "pending"
    end

    test "does not touch already-paid or already-overdue payments" do
      loan = loan_fixture()

      {:ok, paid} =
        Loans.create_payment(%{
          "loan_id" => loan.id,
          "amount" => "10.00",
          "payment_date" => Date.to_iso8601(Date.utc_today()),
          "due_date" => Date.add(Date.utc_today(), -30) |> Date.to_iso8601(),
          "status" => "paid"
        })

      assert Loans.mark_overdue_payments() == 0
      assert Loans.get_payment!(paid.id).status == "paid"
    end
  end

  describe "count_overdue_payments/1 and total_overdue_amount/1" do
    test "counts and totals overdue payments, optionally scoped to a client" do
      loan = approved_loan_fixture(%{"term_months" => "1"})
      other_loan = approved_loan_fixture(%{"term_months" => "1"})

      for l <- [loan, other_loan] do
        [installment] = Loans.list_payments_for_loan(l.id)
        installment |> Ecto.Changeset.change(due_date: Date.add(Date.utc_today(), -5)) |> Repo.update!()
      end

      Loans.mark_overdue_payments()

      assert Loans.count_overdue_payments() == 2
      assert Loans.count_overdue_payments(loan.client_id) == 1

      [loan_installment] = Repo.all(from p in Payment, where: p.loan_id == ^loan.id)
      assert Decimal.equal?(Loans.total_overdue_amount(loan.client_id), loan_installment.amount)
    end

    test "zero when there is no overdue payment" do
      assert Loans.count_overdue_payments() == 0
      assert Decimal.equal?(Loans.total_overdue_amount(), Decimal.new("0.00"))
    end
  end
end
