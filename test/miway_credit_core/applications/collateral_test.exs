defmodule MiwayCreditCore.Applications.CollateralTest do
  use MiwayCreditCore.DataCase, async: true

  import MiwayCreditCore.LoansFixtures
  alias MiwayCreditCore.Applications
  alias MiwayCreditCore.Applications.Collateral
  alias MiwayCreditCore.Accounts.Scope

  describe "create_collateral/2" do
    test "records collateral against an approved account, deriving organisation_id from it" do
      application = approved_application_fixture()
      account = application.loan_account

      attrs = %{"type" => "vehicle", "description" => "Toyota Hilux 2018", "estimated_value" => "45000.00"}

      assert {:ok, %Collateral{} = collateral} = Applications.create_collateral(account, attrs)
      assert collateral.type == "vehicle"
      assert collateral.loan_account_id == account.id
      assert collateral.organisation_id == account.organisation_id
      assert Decimal.equal?(collateral.estimated_value, Decimal.new("45000.00"))
    end

    test "requires type, description, estimated_value" do
      application = approved_application_fixture()
      assert {:error, changeset} = Applications.create_collateral(application.loan_account, %{})
      errors = errors_on(changeset)
      assert errors.type
      assert errors.description
      assert errors.estimated_value
    end

    test "rejects a type outside the allowed list" do
      application = approved_application_fixture()
      attrs = %{"type" => "cryptocurrency", "description" => "x", "estimated_value" => "10"}
      assert {:error, changeset} = Applications.create_collateral(application.loan_account, attrs)
      assert errors_on(changeset).type
    end

    test "rejects a non-positive estimated_value" do
      application = approved_application_fixture()
      attrs = %{"type" => "land", "description" => "x", "estimated_value" => "0"}
      assert {:error, changeset} = Applications.create_collateral(application.loan_account, attrs)
      assert errors_on(changeset).estimated_value
    end
  end

  describe "list_collaterals_for_account/2 and total_collateral_value/2" do
    test "lists only the given account's collateral and sums the value" do
      application = approved_application_fixture()
      other_application = approved_application_fixture()
      account = application.loan_account
      scope = %Scope{organisation_id: account.organisation_id}

      {:ok, _} = Applications.create_collateral(account, %{"type" => "vehicle", "description" => "Car", "estimated_value" => "20000.00"})
      {:ok, _} = Applications.create_collateral(account, %{"type" => "land", "description" => "Plot", "estimated_value" => "30000.00"})
      {:ok, _} = Applications.create_collateral(other_application.loan_account, %{"type" => "electronics", "description" => "Laptop", "estimated_value" => "5000.00"})

      results = Applications.list_collaterals_for_account(scope, account.id)
      assert length(results) == 2

      assert Decimal.equal?(Applications.total_collateral_value(scope, account.id), Decimal.new("50000.00"))
    end

    test "total_collateral_value/2 is zero when no collateral is recorded" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      assert Decimal.equal?(Applications.total_collateral_value(scope, application.loan_account.id), Decimal.new("0.00"))
    end
  end

  describe "get_collateral!/2 and delete_collateral/1" do
    test "fetches and deletes a collateral record" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      {:ok, collateral} = Applications.create_collateral(application.loan_account, %{"type" => "other", "description" => "Jewelry", "estimated_value" => "1500.00"})

      assert Applications.get_collateral!(scope, collateral.id).id == collateral.id
      assert {:ok, _} = Applications.delete_collateral(collateral)
      assert_raise Ecto.NoResultsError, fn -> Applications.get_collateral!(scope, collateral.id) end
    end
  end
end
