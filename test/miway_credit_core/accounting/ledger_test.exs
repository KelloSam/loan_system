defmodule MiwayCreditCore.Accounting.LedgerTest do
  use MiwayCreditCore.DataCase, async: true

  import MiwayCreditCore.LoansFixtures
  alias MiwayCreditCore.{Accounting, Lending}
  alias MiwayCreditCore.Accounts.Scope

  describe "list_entries_for_account/2" do
    test "returns every entry for an account in chronological order" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      payment_fixture(account, %{"amount" => "50.00"})
      payment_fixture(account, %{"amount" => "25.00"})

      entries = Accounting.list_entries_for_account(scope, account.id)
      assert length(entries) == 3
      assert Enum.map(entries, & &1.entry_type) == ["disbursement", "repayment", "repayment"]
      assert entries |> Enum.map(& &1.inserted_at) == Enum.sort(Enum.map(entries, & &1.inserted_at), NaiveDateTime)
    end

    test "only returns entries for the given account" do
      app1 = approved_application_fixture()
      app2 = approved_application_fixture()
      scope1 = %Scope{organisation_id: app1.organisation_id}

      entries1 = Accounting.list_entries_for_account(scope1, app1.loan_account.id)
      assert Enum.all?(entries1, &(&1.loan_account_id == app1.loan_account.id))
      refute Enum.any?(entries1, &(&1.loan_account_id == app2.loan_account.id))
    end
  end

  describe "rebuild_outstanding_balance/2" do
    test "matches the cached outstanding_balance after disbursement and after payments" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      assert Decimal.equal?(Accounting.rebuild_outstanding_balance(scope, account.id), account.outstanding_balance)

      payment_fixture(account, %{"amount" => "50.00"})
      reloaded = Lending.get_account!(scope, account.id)
      assert Decimal.equal?(Accounting.rebuild_outstanding_balance(scope, account.id), reloaded.outstanding_balance)
    end
  end
end
