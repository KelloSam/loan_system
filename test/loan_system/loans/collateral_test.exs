defmodule LoanSystem.Loans.CollateralTest do
  use LoanSystem.DataCase, async: true

  import LoanSystem.LoansFixtures
  alias LoanSystem.Loans
  alias LoanSystem.Loans.Collateral

  describe "create_collateral/1" do
    test "records collateral against a loan" do
      loan = loan_fixture()

      attrs = %{
        "loan_id" => loan.id,
        "type" => "vehicle",
        "description" => "Toyota Hilux 2018",
        "estimated_value" => "45000.00"
      }

      assert {:ok, %Collateral{} = collateral} = Loans.create_collateral(attrs)
      assert collateral.type == "vehicle"
      assert Decimal.equal?(collateral.estimated_value, Decimal.new("45000.00"))
    end

    test "requires type, description, estimated_value, loan_id" do
      assert {:error, changeset} = Loans.create_collateral(%{})
      errors = errors_on(changeset)
      assert errors.type
      assert errors.description
      assert errors.estimated_value
      assert errors.loan_id
    end

    test "rejects a type outside the allowed list" do
      loan = loan_fixture()
      attrs = %{"loan_id" => loan.id, "type" => "cryptocurrency", "description" => "x", "estimated_value" => "10"}
      assert {:error, changeset} = Loans.create_collateral(attrs)
      assert errors_on(changeset).type
    end

    test "rejects a non-positive estimated_value" do
      loan = loan_fixture()
      attrs = %{"loan_id" => loan.id, "type" => "land", "description" => "x", "estimated_value" => "0"}
      assert {:error, changeset} = Loans.create_collateral(attrs)
      assert errors_on(changeset).estimated_value
    end
  end

  describe "list_collaterals_for_loan/1 and total_collateral_value/1" do
    test "lists only the given loan's collateral and sums the value" do
      loan = loan_fixture()
      other_loan = loan_fixture()

      {:ok, _} = Loans.create_collateral(%{"loan_id" => loan.id, "type" => "vehicle", "description" => "Car", "estimated_value" => "20000.00"})
      {:ok, _} = Loans.create_collateral(%{"loan_id" => loan.id, "type" => "land", "description" => "Plot", "estimated_value" => "30000.00"})
      {:ok, _} = Loans.create_collateral(%{"loan_id" => other_loan.id, "type" => "electronics", "description" => "Laptop", "estimated_value" => "5000.00"})

      results = Loans.list_collaterals_for_loan(loan.id)
      assert length(results) == 2

      assert Decimal.equal?(Loans.total_collateral_value(loan.id), Decimal.new("50000.00"))
    end

    test "total_collateral_value/1 is zero when no collateral is recorded" do
      loan = loan_fixture()
      assert Decimal.equal?(Loans.total_collateral_value(loan.id), Decimal.new("0.00"))
    end
  end

  describe "get_collateral!/1 and delete_collateral/1" do
    test "fetches and deletes a collateral record" do
      loan = loan_fixture()
      {:ok, collateral} = Loans.create_collateral(%{"loan_id" => loan.id, "type" => "other", "description" => "Jewelry", "estimated_value" => "1500.00"})

      assert Loans.get_collateral!(collateral.id).id == collateral.id
      assert {:ok, _} = Loans.delete_collateral(collateral)
      assert_raise Ecto.NoResultsError, fn -> Loans.get_collateral!(collateral.id) end
    end
  end

  describe "deleting a loan cascades to its collateral" do
    test "collateral is removed when the loan is deleted" do
      loan = loan_fixture()
      {:ok, collateral} = Loans.create_collateral(%{"loan_id" => loan.id, "type" => "vehicle", "description" => "Car", "estimated_value" => "20000.00"})

      {:ok, _} = Loans.delete_loan(loan)
      assert_raise Ecto.NoResultsError, fn -> Loans.get_collateral!(collateral.id) end
    end
  end
end
