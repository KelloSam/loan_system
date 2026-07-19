defmodule LoanSystem.ReportsTest do
  use LoanSystem.DataCase, async: true

  import LoanSystem.{ClientsFixtures, LoansFixtures}
  alias LoanSystem.{Loans, Reports, Repo}

  describe "portfolio_summary/0" do
    test "reflects current portfolio state" do
      client_fixture()
      loan = loan_fixture()

      summary = Reports.portfolio_summary()
      assert summary.total_clients >= 1
      assert summary.total_loans >= 1
      assert summary.active_loans >= 1
      assert Decimal.compare(summary.outstanding_balance, Decimal.new("0")) != :lt

      {:ok, _} = Loans.reject_loan(loan)
      after_reject = Reports.portfolio_summary()
      assert after_reject.active_loans == summary.active_loans - 1
    end
  end

  describe "overdue_payments/0" do
    test "lists overdue installments oldest-first, with loan and client preloaded" do
      loan = approved_loan_fixture(%{"term_months" => "1"})
      [installment] = Loans.list_payments_for_loan(loan.id)

      installment
      |> Ecto.Changeset.change(due_date: Date.add(Date.utc_today(), -3))
      |> Repo.update!()

      Loans.mark_overdue_payments()

      assert [found] = Reports.overdue_payments()
      assert found.id == installment.id
      assert found.loan.id == loan.id
      assert found.loan.client.id == loan.client_id
    end
  end

  describe "payments_due_soon/1" do
    test "returns pending installments due within the window, not overdue ones" do
      loan = approved_loan_fixture(%{"term_months" => "1"})
      [installment] = Loans.list_payments_for_loan(loan.id)

      installment
      |> Ecto.Changeset.change(due_date: Date.add(Date.utc_today(), 3))
      |> Repo.update!()

      due_soon = Reports.payments_due_soon(7)
      assert Enum.any?(due_soon, &(&1.id == installment.id))

      far_out = Reports.payments_due_soon(1)
      refute Enum.any?(far_out, &(&1.id == installment.id))
    end
  end

  describe "loans_csv/0" do
    test "produces a header row plus one row per loan" do
      client = client_fixture(%{name: "CSV, Client \"Test\""})
      loan_fixture(%{"client_id" => client.id})

      csv = Reports.loans_csv()
      lines = String.split(csv, "\r\n", trim: true)

      assert hd(lines) == "loan_id,client_name,status,risk_level,amount,remaining_balance,approved_at"
      assert length(lines) >= 2
      # a client name containing a comma and quotes must be properly CSV-escaped
      assert Enum.any?(lines, &(&1 =~ ~s("CSV, Client ""Test""")))
    end
  end
end
