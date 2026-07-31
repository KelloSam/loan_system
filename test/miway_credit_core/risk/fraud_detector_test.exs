defmodule MiwayCreditCore.Risk.FraudDetectorTest do
  use MiwayCreditCore.DataCase, async: true

  import MiwayCreditCore.CustomersFixtures
  import MiwayCreditCore.AccountsFixtures
  import MiwayCreditCore.LoansFixtures
  alias MiwayCreditCore.Risk.FraudDetector
  alias MiwayCreditCore.Applications
  alias MiwayCreditCore.Accounts.Scope

  describe "evaluate/3 — classification thresholds" do
    test "no customer tied and a non-round amount scores 0 (low)" do
      assert {"low", 0, []} = FraudDetector.evaluate(nil, "1234.56")
    end

    test "a fresh customer's first loan is always at least medium risk" do
      customer = customer_fixture()
      {level, score, signals} = FraudDetector.evaluate(customer.id, "1234.56")
      assert level == "medium"
      assert score == 35
      assert Enum.any?(signals, &(&1 =~ "less than 7 days old"))
      assert Enum.any?(signals, &(&1 =~ "No repayment history"))
    end

    test "a fresh customer's large first loan crosses into high risk" do
      customer = customer_fixture()
      {level, score, signals} = FraudDetector.evaluate(customer.id, "6500")
      assert level == "high"
      assert score == 60
      assert Enum.any?(signals, &(&1 =~ "First loan request"))
    end
  end

  describe "evaluate/3 — individual signals" do
    test "signal_round_amount fires for amounts divisible by 1000, independent of customer" do
      {_level, score, signals} = FraudDetector.evaluate(nil, "3000")
      assert score == 10
      assert Enum.any?(signals, &(&1 =~ "round figure"))
    end

    test "no_repayment_history clears once the customer has a disbursed application" do
      customer = customer_fixture()
      application = application_fixture(%{"customer_id" => customer.id})
      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      {:ok, assessed} = Applications.assess_application(application, admin_scope)
      {:ok, approved} = Applications.approve_application(assessed, admin_scope, true)
      {:ok, _disbursed, _account} = Applications.disburse_application(approved, admin_scope)

      {_level, _score, signals} = FraudDetector.evaluate(customer.id, "1234.56")
      refute Enum.any?(signals, &(&1 =~ "No repayment history"))
    end

    test "amount_vs_average fires when the new amount exceeds 3x the customer's disbursed average" do
      customer = customer_fixture()
      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}

      prior =
        application_fixture(%{"customer_id" => customer.id, "requested_amount" => "1000.50"})

      {:ok, assessed} = Applications.assess_application(prior, admin_scope)
      {:ok, approved} = Applications.approve_application(assessed, admin_scope, true)
      {:ok, _disbursed, _account} = Applications.disburse_application(approved, admin_scope)

      {_level, _score, signals} = FraudDetector.evaluate(customer.id, "5000")
      assert Enum.any?(signals, &(&1 =~ "3× the customer's average"))
    end

    test "recent_rejection fires within 90 days of a rejected application" do
      customer = customer_fixture()
      application = application_fixture(%{"customer_id" => customer.id})
      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      {:ok, assessed} = Applications.assess_application(application, admin_scope)
      {:ok, _rejected} = Applications.reject_application(assessed, admin_scope, "Not eligible")

      {_level, _score, signals} = FraudDetector.evaluate(customer.id, "1234.56")
      assert Enum.any?(signals, &(&1 =~ "rejected within the last 90 days"))
    end

    test "exclude_application_id leaves the application being re-evaluated out of its own history" do
      customer = customer_fixture()
      application = application_fixture(%{"customer_id" => customer.id})
      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      {:ok, assessed} = Applications.assess_application(application, admin_scope)
      {:ok, approved0} = Applications.approve_application(assessed, admin_scope, true)
      {:ok, approved, _account} = Applications.disburse_application(approved0, admin_scope)

      # Without excluding: the application counts as its own repayment history.
      {_level, _score, signals_included} = FraudDetector.evaluate(customer.id, "1234.56")
      refute Enum.any?(signals_included, &(&1 =~ "No repayment history"))

      # Excluding it: back to "no history", since that's the only application.
      {_level, _score, signals_excluded} =
        FraudDetector.evaluate(customer.id, "1234.56", approved.id)

      assert Enum.any?(signals_excluded, &(&1 =~ "No repayment history"))
    end
  end
end
