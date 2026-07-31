defmodule MiwayCreditCore.Risk.AffordabilityCalculatorTest do
  use MiwayCreditCore.DataCase, async: true

  import MiwayCreditCore.CustomersFixtures
  import MiwayCreditCore.LoansFixtures

  alias MiwayCreditCore.Risk
  alias MiwayCreditCore.Applications.LoanApplication
  alias MiwayCreditCore.Products.LoanProduct
  alias MiwayCreditCore.Accounts.Scope

  describe "assess_affordability/3" do
    test "passes when the proposed installment stays within the ratio" do
      customer = customer_fixture(%{"monthly_income" => "5000"})
      scope = %Scope{organisation_id: customer.organisation_id}

      assert :ok =
               Risk.assess_affordability(
                 scope,
                 application_stub(customer, "1000", 12),
                 product_stub("18.00", "40.00")
               )
    end

    test "fails when the proposed installment alone exceeds the ratio" do
      customer = customer_fixture(%{"monthly_income" => "500"})
      scope = %Scope{organisation_id: customer.organisation_id}

      assert {:error, :affordability_exceeded} =
               Risk.assess_affordability(
                 scope,
                 application_stub(customer, "10000", 12),
                 product_stub("18.00", "40.00")
               )
    end

    test "passes right at the threshold, fails just over it" do
      customer = customer_fixture(%{"monthly_income" => "1000"})
      scope = %Scope{organisation_id: customer.organisation_id}
      # 40% of 1000 income = 400; pick an amount/term whose PMT lands under vs over that.
      assert :ok =
               Risk.assess_affordability(
                 scope,
                 application_stub(customer, "4000", 12),
                 product_stub("0", "40.00")
               )

      assert {:error, :affordability_exceeded} =
               Risk.assess_affordability(
                 scope,
                 application_stub(customer, "5000", 12),
                 product_stub("0", "40.00")
               )
    end

    test "fails closed when the individual customer has no monthly_income on file" do
      customer = customer_fixture()
      scope = %Scope{organisation_id: customer.organisation_id}

      assert {:error, :income_data_missing} =
               Risk.assess_affordability(
                 scope,
                 application_stub(customer, "1000", 12),
                 product_stub("18.00", "40.00")
               )
    end

    test "uses annual_turnover / 12 as the income proxy for a business customer" do
      customer =
        customer_fixture(%{
          "customer_type" => "business",
          "id_type" => "company_registration",
          "annual_turnover" => "120000"
        })

      scope = %Scope{organisation_id: customer.organisation_id}

      assert :ok =
               Risk.assess_affordability(
                 scope,
                 application_stub(customer, "1000", 12),
                 product_stub("18.00", "40.00")
               )
    end

    test "fails closed when the business customer has no annual_turnover on file" do
      customer =
        customer_fixture(%{"customer_type" => "business", "id_type" => "company_registration"})

      scope = %Scope{organisation_id: customer.organisation_id}

      assert {:error, :income_data_missing} =
               Risk.assess_affordability(
                 scope,
                 application_stub(customer, "1000", 12),
                 product_stub("18.00", "40.00")
               )
    end

    test "counts an existing active account's monthly obligation toward the ratio" do
      customer = customer_fixture(%{"monthly_income" => "1000"})
      # ~40% of 1000 income; an existing loan alone should already eat most of that.
      _existing =
        approved_application_fixture(%{
          "customer_id" => customer.id,
          "requested_amount" => "5000",
          "requested_term_months" => "24"
        })

      scope = %Scope{organisation_id: customer.organisation_id}

      assert {:error, :affordability_exceeded} =
               Risk.assess_affordability(
                 scope,
                 application_stub(customer, "3000", 12),
                 product_stub("18.00", "40.00")
               )
    end
  end

  defp application_stub(customer, amount, term_months) do
    %LoanApplication{
      customer_id: customer.id,
      requested_amount: Decimal.new(amount),
      requested_term_months: term_months
    }
  end

  defp product_stub(interest_rate, max_debt_to_income_percent) do
    %LoanProduct{
      interest_rate: Decimal.new(interest_rate),
      max_debt_to_income_percent: Decimal.new(max_debt_to_income_percent)
    }
  end
end
