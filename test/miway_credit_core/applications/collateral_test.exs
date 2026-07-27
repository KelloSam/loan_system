defmodule MiwayCreditCore.Applications.CollateralTest do
  use MiwayCreditCore.DataCase, async: true

  import MiwayCreditCore.LoansFixtures
  alias MiwayCreditCore.Applications
  alias MiwayCreditCore.Applications.Collateral

  describe "create_collateral/1" do
    test "records collateral against an approved account" do
      application = approved_application_fixture()

      attrs = %{
        "loan_account_id" => application.loan_account.id,
        "type" => "vehicle",
        "description" => "Toyota Hilux 2018",
        "estimated_value" => "45000.00"
      }

      assert {:ok, %Collateral{} = collateral} = Applications.create_collateral(attrs)
      assert collateral.type == "vehicle"
      assert Decimal.equal?(collateral.estimated_value, Decimal.new("45000.00"))
    end

    test "requires type, description, estimated_value, loan_account_id" do
      assert {:error, changeset} = Applications.create_collateral(%{})
      errors = errors_on(changeset)
      assert errors.type
      assert errors.description
      assert errors.estimated_value
      assert errors.loan_account_id
    end

    test "rejects a type outside the allowed list" do
      application = approved_application_fixture()
      attrs = %{"loan_account_id" => application.loan_account.id, "type" => "cryptocurrency", "description" => "x", "estimated_value" => "10"}
      assert {:error, changeset} = Applications.create_collateral(attrs)
      assert errors_on(changeset).type
    end

    test "rejects a non-positive estimated_value" do
      application = approved_application_fixture()
      attrs = %{"loan_account_id" => application.loan_account.id, "type" => "land", "description" => "x", "estimated_value" => "0"}
      assert {:error, changeset} = Applications.create_collateral(attrs)
      assert errors_on(changeset).estimated_value
    end
  end

  describe "list_collaterals_for_account/1 and total_collateral_value/1" do
    test "lists only the given account's collateral and sums the value" do
      application = approved_application_fixture()
      other_application = approved_application_fixture()
      account_id = application.loan_account.id

      {:ok, _} = Applications.create_collateral(%{"loan_account_id" => account_id, "type" => "vehicle", "description" => "Car", "estimated_value" => "20000.00"})
      {:ok, _} = Applications.create_collateral(%{"loan_account_id" => account_id, "type" => "land", "description" => "Plot", "estimated_value" => "30000.00"})
      {:ok, _} = Applications.create_collateral(%{"loan_account_id" => other_application.loan_account.id, "type" => "electronics", "description" => "Laptop", "estimated_value" => "5000.00"})

      results = Applications.list_collaterals_for_account(account_id)
      assert length(results) == 2

      assert Decimal.equal?(Applications.total_collateral_value(account_id), Decimal.new("50000.00"))
    end

    test "total_collateral_value/1 is zero when no collateral is recorded" do
      application = approved_application_fixture()
      assert Decimal.equal?(Applications.total_collateral_value(application.loan_account.id), Decimal.new("0.00"))
    end
  end

  describe "get_collateral!/1 and delete_collateral/1" do
    test "fetches and deletes a collateral record" do
      application = approved_application_fixture()
      {:ok, collateral} = Applications.create_collateral(%{"loan_account_id" => application.loan_account.id, "type" => "other", "description" => "Jewelry", "estimated_value" => "1500.00"})

      assert Applications.get_collateral!(collateral.id).id == collateral.id
      assert {:ok, _} = Applications.delete_collateral(collateral)
      assert_raise Ecto.NoResultsError, fn -> Applications.get_collateral!(collateral.id) end
    end
  end
end
