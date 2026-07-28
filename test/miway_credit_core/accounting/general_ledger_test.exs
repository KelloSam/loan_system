defmodule MiwayCreditCore.Accounting.GeneralLedgerTest do
  use MiwayCreditCore.DataCase, async: true

  import Ecto.Query
  import MiwayCreditCore.LoansFixtures
  import MiwayCreditCore.AccountsFixtures
  alias MiwayCreditCore.{Repo, Accounting, Applications, Lending, Products}
  alias MiwayCreditCore.Accounting.GeneralLedger
  alias MiwayCreditCore.Accounts.Scope

  describe "post_journal_entry/3" do
    test "refuses an unbalanced set of lines — nothing is inserted" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      before = Accounting.trial_balance(scope)

      result =
        Ecto.Multi.new()
        |> GeneralLedger.post_journal_entry(:bad, %{
          organisation_id: account.organisation_id,
          description: "unbalanced test",
          source_type: "loan_account",
          source_id: account.id,
          occurred_at: DateTime.utc_now() |> DateTime.truncate(:second),
          lines: [%{account_code: "1100", debit: Decimal.new("10.00")}]
        })
        |> Repo.transaction()

      assert {:error, :bad, {:unbalanced_journal_entry, _, _}, _} = result
      assert Accounting.trial_balance(scope) == before
    end

    test "a zero-amount line set posts nothing rather than an empty header" do
      application = approved_application_fixture()
      account = application.loan_account
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      multi =
        Ecto.Multi.new()
        |> GeneralLedger.post_journal_entry(:noop, %{
          organisation_id: account.organisation_id,
          description: "zero fee",
          source_type: "loan_account",
          source_id: account.id,
          occurred_at: now,
          lines: [%{account_code: "1100", debit: Decimal.new("0")}, %{account_code: "4100", credit: Decimal.new("0")}]
        })

      assert multi == Ecto.Multi.new()
    end
  end

  describe "disbursement posts a balanced journal entry" do
    test "no fee — Loans Receivable / Cash-side / Interest Income" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account

      lines = lines_for_source(scope, "loan_account", account.id)
      assert length(lines) == 3

      receivable = Enum.find(lines, &(&1.code == "1100"))
      cash = Enum.find(lines, &(&1.code == "1010"))
      interest = Enum.find(lines, &(&1.code == "4000"))

      assert Decimal.equal?(receivable.debit_amount, account.outstanding_balance)
      assert Decimal.equal?(cash.credit_amount, account.principal_amount)
      assert Decimal.equal?(interest.credit_amount, Decimal.sub(account.outstanding_balance, account.principal_amount))
      assert Accounting.trial_balance(scope).balanced?
    end

    test "with an origination fee — a second balanced entry adds Fee Income" do
      customer = MiwayCreditCore.CustomersFixtures.customer_fixture()
      scope = scope_for_customer_id(customer.id)
      {:ok, product} =
        Products.create_product(scope, %{
          "name" => "Fee Product", "minimum_principal" => "0.01", "maximum_principal" => "999999.99",
          "interest_method" => "reducing_balance", "interest_rate" => "18.00", "minimum_term_months" => "1",
          "maximum_term_months" => "12", "repayment_frequency" => "monthly",
          "origination_fee_percent" => "5.00", "effective_from" => Date.utc_today()
        })

      application = application_fixture(%{"customer_id" => customer.id, "loan_product_id" => product.id})
      admin = admin_fixture()
      admin_scope = %Scope{user: admin, organisation_id: :all}
      {:ok, assessed} = Applications.assess_application(application, admin_scope)
      {:ok, approved} = Applications.approve_application(assessed, admin_scope, true)
      {:ok, _disbursed, account} = Applications.disburse_application(approved, admin_scope)

      lines = lines_for_source(scope, "loan_account", account.id)
      assert length(lines) == 5

      fee_income = Enum.find(lines, &(&1.code == "4100"))
      assert Decimal.equal?(fee_income.credit_amount, Decimal.new("61.73"))
      assert Accounting.trial_balance(scope).balanced?
    end
  end

  describe "repayment / void" do
    test "repayment debits the method's cash-side account and credits Loans Receivable" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      transaction = payment_fixture(account, %{"amount" => "50.00", "method" => "mobile_money"})

      lines = lines_for_source(scope, "payment_transaction", transaction.id)
      cash = Enum.find(lines, &(&1.code == "1020"))
      receivable = Enum.find(lines, &(&1.code == "1100"))

      assert Decimal.equal?(cash.debit_amount, Decimal.new("50.00"))
      assert Decimal.equal?(receivable.credit_amount, Decimal.new("50.00"))
      assert Accounting.trial_balance(scope).balanced?
    end

    test "voiding a payment nets Loans Receivable back to zero for that transaction, and stays balanced" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      transaction = payment_fixture(account, %{"amount" => "50.00"})
      admin = admin_fixture()

      {:ok, _voided} = MiwayCreditCore.Payments.void_payment(transaction, %{
        "voided_by_id" => admin.id, "void_reason" => "test"
      })

      net_receivable = net_for_account_code(scope, "payment_transaction", transaction.id, "1100")
      assert Decimal.equal?(net_receivable, Decimal.new("0.00"))
      assert Accounting.trial_balance(scope).balanced?
    end
  end

  describe "reverse_disbursement/3" do
    test "generically undoes the disbursement — every account nets to zero for that source" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      admin = admin_fixture()

      {:ok, _reversed} = Lending.reverse_disbursement(account, admin.id, "Wrong customer")

      for code <- ["1100", "1010", "4000"] do
        net = net_for_account_code(scope, "loan_account", account.id, code)
        assert Decimal.equal?(net, Decimal.new("0.00")), "expected #{code} to net to zero, got #{net}"
      end

      assert Accounting.trial_balance(scope).balanced?
    end
  end

  describe "write_off_account/2" do
    test "posts Bad Debt Expense / Loans Receivable and stays balanced" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      admin = admin_fixture()
      outstanding = account.outstanding_balance

      {:ok, _written_off} = Lending.write_off_account(account, admin.id)

      lines = lines_for_source(scope, "manual_adjustment", nil)
      expense = Enum.find(lines, &(&1.code == "5000"))
      receivable = Enum.find(lines, &(&1.code == "1100"))

      assert Decimal.equal?(expense.debit_amount, outstanding)
      assert Decimal.equal?(receivable.credit_amount, outstanding)
      assert Accounting.trial_balance(scope).balanced?
    end
  end

  describe "cash_position/1" do
    test "reflects the right method-account after cash vs mobile-money payments" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account

      payment_fixture(account, %{"amount" => "30.00", "method" => "cash"})
      payment_fixture(account, %{"amount" => "20.00", "method" => "mobile_money"})

      position = Accounting.cash_position(scope)
      cash = Enum.find(position, &(&1.code == "1000"))
      mobile_money = Enum.find(position, &(&1.code == "1020"))

      assert Decimal.equal?(cash.balance, Decimal.new("30.00"))
      assert Decimal.equal?(mobile_money.balance, Decimal.new("20.00"))
    end
  end

  defp lines_for_source(%Scope{} = scope, source_type, source_id) do
    MiwayCreditCore.Accounting.JournalLine
    |> where([jl], jl.organisation_id == ^scope.organisation_id)
    |> join(:inner, [jl], je in MiwayCreditCore.Accounting.JournalEntry, on: je.id == jl.journal_entry_id)
    |> join(:inner, [jl, je], a in MiwayCreditCore.Accounting.Account, on: a.id == jl.account_id)
    |> where([jl, je], je.source_type == ^source_type)
    |> maybe_filter_source_id(source_id)
    |> select([jl, je, a], %{code: a.code, debit_amount: jl.debit_amount, credit_amount: jl.credit_amount})
    |> Repo.all()
  end

  defp maybe_filter_source_id(query, nil), do: query
  defp maybe_filter_source_id(query, source_id) do
    where(query, [jl, je], je.source_id == ^source_id)
  end

  defp net_for_account_code(%Scope{} = scope, source_type, source_id, code) do
    lines_for_source(scope, source_type, source_id)
    |> Enum.filter(&(&1.code == code))
    |> Enum.reduce(Decimal.new("0"), fn line, acc ->
      acc
      |> Decimal.add(line.debit_amount || Decimal.new("0"))
      |> Decimal.sub(line.credit_amount || Decimal.new("0"))
    end)
  end
end
