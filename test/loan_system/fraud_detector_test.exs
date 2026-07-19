defmodule LoanSystem.FraudDetectorTest do
  use LoanSystem.DataCase, async: true

  import LoanSystem.ClientsFixtures
  import LoanSystem.LoansFixtures
  alias LoanSystem.FraudDetector
  alias LoanSystem.Loans

  describe "evaluate/3 — classification thresholds" do
    test "no client tied and a non-round amount scores 0 (low)" do
      assert {"low", 0, []} = FraudDetector.evaluate(nil, "1234.56")
    end

    test "a fresh client's first loan is always at least medium risk" do
      client = client_fixture()
      {level, score, signals} = FraudDetector.evaluate(client.id, "1234.56")
      assert level == "medium"
      assert score == 35
      assert Enum.any?(signals, &(&1 =~ "less than 7 days old"))
      assert Enum.any?(signals, &(&1 =~ "No repayment history"))
    end

    test "a fresh client's large first loan crosses into high risk" do
      client = client_fixture()
      {level, score, signals} = FraudDetector.evaluate(client.id, "6500")
      assert level == "high"
      assert score == 60
      assert Enum.any?(signals, &(&1 =~ "First loan request"))
    end
  end

  describe "evaluate/3 — individual signals" do
    test "signal_round_amount fires for amounts divisible by 1000, independent of client" do
      {_level, score, signals} = FraudDetector.evaluate(nil, "3000")
      assert score == 10
      assert Enum.any?(signals, &(&1 =~ "round figure"))
    end

    test "no_repayment_history clears once the client has an approved loan" do
      client = client_fixture()
      loan = loan_fixture(%{"client_id" => client.id})
      {:ok, _approved} = Loans.approve_loan(loan)

      {_level, _score, signals} = FraudDetector.evaluate(client.id, "1234.56")
      refute Enum.any?(signals, &(&1 =~ "No repayment history"))
    end

    test "amount_vs_average fires when the new amount exceeds 3x the client's approved average" do
      client = client_fixture()
      prior = loan_fixture(%{"client_id" => client.id, "amount" => "1000.50", "remaining_balance" => "1000.50"})
      {:ok, _approved} = Loans.approve_loan(prior)

      {_level, _score, signals} = FraudDetector.evaluate(client.id, "5000")
      assert Enum.any?(signals, &(&1 =~ "3× the client's average"))
    end

    test "recent_rejection fires within 90 days of a rejected loan" do
      client = client_fixture()
      loan = loan_fixture(%{"client_id" => client.id})
      {:ok, _rejected} = Loans.reject_loan(loan)

      {_level, _score, signals} = FraudDetector.evaluate(client.id, "1234.56")
      assert Enum.any?(signals, &(&1 =~ "rejected within the last 90 days"))
    end

    test "exclude_loan_id leaves the loan being re-evaluated out of its own history" do
      client = client_fixture()
      loan = loan_fixture(%{"client_id" => client.id})
      {:ok, approved} = Loans.approve_loan(loan)

      # Without excluding: the loan counts as its own repayment history.
      {_level, _score, signals_included} = FraudDetector.evaluate(client.id, "1234.56")
      refute Enum.any?(signals_included, &(&1 =~ "No repayment history"))

      # Excluding it: back to "no history", since that's the only loan.
      {_level, _score, signals_excluded} = FraudDetector.evaluate(client.id, "1234.56", approved.id)
      assert Enum.any?(signals_excluded, &(&1 =~ "No repayment history"))
    end
  end
end
