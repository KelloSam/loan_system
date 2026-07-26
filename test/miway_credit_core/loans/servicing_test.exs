defmodule MiwayCreditCore.Loans.ServicingTest do
  use MiwayCreditCore.DataCase, async: true

  import MiwayCreditCore.LoansFixtures
  import MiwayCreditCore.AccountsFixtures
  alias MiwayCreditCore.Loans
  alias MiwayCreditCore.Customers

  describe "get_account!/1 and list_accounts_for_customer/1" do
    test "fetches an account with application and customer preloaded" do
      application = approved_application_fixture()
      account = Loans.get_account!(application.loan_account.id)

      assert account.id == application.loan_account.id
      assert account.loan_application.id == application.id
      assert account.customer.id == application.customer_id
    end

    test "lists every account for a customer" do
      application = approved_application_fixture()
      accounts = Loans.list_accounts_for_customer(application.customer_id)

      assert [found] = accounts
      assert found.id == application.loan_account.id
    end
  end

  describe "close_account/1" do
    test "sets status closed and stamps closed_at" do
      application = approved_application_fixture()
      assert {:ok, closed} = Loans.close_account(application.loan_account)
      assert closed.status == "closed"
      assert closed.closed_at
    end
  end

  describe "write_off_account/2" do
    test "zeroes the balance, posts a write_off ledger entry, and recalculates customer stats" do
      application = approved_application_fixture()
      account = application.loan_account
      admin = admin_fixture()

      assert {:ok, written_off} = Loans.write_off_account(account, admin.id)
      assert written_off.status == "written_off"
      assert Decimal.equal?(written_off.outstanding_balance, Decimal.new("0.00"))

      entries = Loans.list_entries_for_account(account.id)
      assert Enum.any?(entries, &(&1.entry_type == "write_off"))
      assert Decimal.equal?(Loans.rebuild_outstanding_balance(account.id), Decimal.new("0.00"))

      reloaded_customer = Customers.get_customer!(application.customer_id)
      assert Decimal.equal?(reloaded_customer.current_balance, Decimal.new("0.00"))
    end
  end

  describe "aggregate counters" do
    test "count_active_accounts/0 and total_outstanding_balance/0" do
      active_before = Loans.count_active_accounts()
      outstanding_before = Loans.total_outstanding_balance()

      application = approved_application_fixture()
      account = application.loan_account

      assert Loans.count_active_accounts() == active_before + 1
      assert Decimal.equal?(
               Loans.total_outstanding_balance(),
               Decimal.add(outstanding_before, account.outstanding_balance)
             )

      {:ok, _} = Loans.close_account(account)
      assert Loans.count_active_accounts() == active_before
    end
  end
end
