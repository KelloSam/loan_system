defmodule MiwayCreditCore.Lending.ServicingTest do
  use MiwayCreditCore.DataCase, async: true

  import MiwayCreditCore.LoansFixtures
  import MiwayCreditCore.AccountsFixtures
  alias MiwayCreditCore.{Lending, Accounting, Customers}
  alias MiwayCreditCore.Accounts.Scope

  describe "get_account!/1 and list_accounts_for_customer/1" do
    test "fetches an account with application and customer preloaded" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = Lending.get_account!(scope, application.loan_account.id)

      assert account.id == application.loan_account.id
      assert account.loan_application.id == application.id
      assert account.customer.id == application.customer_id
    end

    test "lists every account for a customer" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      accounts = Lending.list_accounts_for_customer(scope, application.customer_id)

      assert [found] = accounts
      assert found.id == application.loan_account.id
    end
  end

  describe "close_account/1" do
    test "sets status closed and stamps closed_at" do
      application = approved_application_fixture()
      assert {:ok, closed} = Lending.close_account(application.loan_account)
      assert closed.status == "closed"
      assert closed.closed_at
    end
  end

  describe "write_off_account/2" do
    test "zeroes the balance, posts a write_off ledger entry, and recalculates customer stats" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      admin = admin_fixture()

      assert {:ok, written_off} = Lending.write_off_account(account, admin.id)
      assert written_off.status == "written_off"
      assert Decimal.equal?(written_off.outstanding_balance, Decimal.new("0.00"))

      entries = Accounting.list_entries_for_account(scope, account.id)
      assert Enum.any?(entries, &(&1.entry_type == "write_off"))
      assert Decimal.equal?(Accounting.rebuild_outstanding_balance(scope, account.id), Decimal.new("0.00"))

      reloaded_customer = Customers.get_customer!(scope, application.customer_id)
      assert Decimal.equal?(reloaded_customer.current_balance, Decimal.new("0.00"))
    end
  end

  describe "reverse_disbursement/3" do
    test "zeroes the balance, posts a reversal ledger entry, and recalculates customer stats" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      admin = admin_fixture()

      assert {:ok, reversed} = Lending.reverse_disbursement(account, admin.id, "Disbursed to the wrong customer")
      assert reversed.status == "reversed"
      assert reversed.reversed_at
      assert reversed.reversal_reason == "Disbursed to the wrong customer"
      assert Decimal.equal?(reversed.outstanding_balance, Decimal.new("0.00"))

      entries = Accounting.list_entries_for_account(scope, account.id)
      assert Enum.any?(entries, &(&1.entry_type == "reversal"))
      assert Decimal.equal?(Accounting.rebuild_outstanding_balance(scope, account.id), Decimal.new("0.00"))

      reloaded_customer = Customers.get_customer!(scope, application.customer_id)
      assert Decimal.equal?(reloaded_customer.current_balance, Decimal.new("0.00"))
    end

    test "excludes a reversed account from count_active_accounts/1 and total_outstanding_balance/1" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      admin = admin_fixture()

      assert Lending.count_active_accounts(scope) == 1
      {:ok, _} = Lending.reverse_disbursement(account, admin.id, "Wrong customer")
      assert Lending.count_active_accounts(scope) == 0
      assert Decimal.equal?(Lending.total_outstanding_balance(scope), Decimal.new("0.00"))
    end

    test "refuses once a posted payment has been recorded against the account" do
      application = approved_application_fixture()
      account = application.loan_account
      admin = admin_fixture()
      _transaction = payment_fixture(account)

      assert {:error, :payments_already_received} = Lending.reverse_disbursement(account, admin.id, "Too late now")
    end

    test "refuses on an account that isn't active" do
      application = approved_application_fixture()
      account = application.loan_account
      admin = admin_fixture()
      {:ok, closed} = Lending.close_account(account)

      assert {:error, :invalid_status} = Lending.reverse_disbursement(closed, admin.id, "Too late")
    end
  end

  describe "aggregate counters" do
    test "count_active_accounts/0 and total_outstanding_balance/0 are scoped to one organisation" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account

      assert Lending.count_active_accounts(scope) == 1
      assert Decimal.equal?(Lending.total_outstanding_balance(scope), account.outstanding_balance)

      # A second organisation's account never affects this scope's counters.
      other_application = approved_application_fixture()
      other_scope = %Scope{organisation_id: other_application.organisation_id}
      assert Lending.count_active_accounts(scope) == 1
      assert Lending.count_active_accounts(other_scope) == 1

      {:ok, _} = Lending.close_account(account)
      assert Lending.count_active_accounts(scope) == 0
    end
  end
end
