defmodule MiwayCreditCore.Loans.LedgerTest do
  use MiwayCreditCore.DataCase, async: true

  import MiwayCreditCore.LoansFixtures
  alias MiwayCreditCore.Loans

  describe "list_entries_for_account/1" do
    test "returns every entry for an account in chronological order" do
      application = approved_application_fixture()
      account = application.loan_account
      payment_fixture(account, %{"amount" => "50.00"})
      payment_fixture(account, %{"amount" => "25.00"})

      entries = Loans.list_entries_for_account(account.id)
      assert length(entries) == 3
      assert Enum.map(entries, & &1.entry_type) == ["disbursement", "repayment", "repayment"]
      assert entries |> Enum.map(& &1.inserted_at) == Enum.sort(Enum.map(entries, & &1.inserted_at), NaiveDateTime)
    end

    test "only returns entries for the given account" do
      app1 = approved_application_fixture()
      app2 = approved_application_fixture()

      entries1 = Loans.list_entries_for_account(app1.loan_account.id)
      assert Enum.all?(entries1, &(&1.loan_account_id == app1.loan_account.id))
      refute Enum.any?(entries1, &(&1.loan_account_id == app2.loan_account.id))
    end
  end

  describe "rebuild_outstanding_balance/1" do
    test "matches the cached outstanding_balance after disbursement and after payments" do
      application = approved_application_fixture()
      account = application.loan_account
      assert Decimal.equal?(Loans.rebuild_outstanding_balance(account.id), account.outstanding_balance)

      payment_fixture(account, %{"amount" => "50.00"})
      reloaded = Loans.get_account!(account.id)
      assert Decimal.equal?(Loans.rebuild_outstanding_balance(account.id), reloaded.outstanding_balance)
    end
  end
end
