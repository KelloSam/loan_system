defmodule MiwayCreditCore.Risk.AffordabilityCalculator do
  @moduledoc """
  Debt-to-income affordability check for a loan application:
  (existing monthly obligations + proposed installment) / gross
  monthly income, compared against the product's
  max_debt_to_income_percent. A pass/fail gate, not a scored signal —
  that's why it's a separate function from `FraudDetector`, not
  another signal folded into its score. Internal to Risk — callers go
  through `MiwayCreditCore.Risk.assess_affordability/3`, not this
  module directly.
  """

  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.Lending
  alias MiwayCreditCore.Lending.InterestCalculator
  alias MiwayCreditCore.Customers.Customer
  alias MiwayCreditCore.Applications.LoanApplication
  alias MiwayCreditCore.Products.LoanProduct
  alias MiwayCreditCore.Accounts.Scope

  @doc """
  `:ok` if the application clears the product's max_debt_to_income_percent,
  `{:error, :income_data_missing}` if the customer has no usable income
  figure on file (fails closed — never treated as affordable),
  `{:error, :affordability_exceeded}` otherwise.
  """
  def assess(%Scope{} = scope, %LoanApplication{} = application, %LoanProduct{} = product) do
    customer = Repo.get!(Customer, application.customer_id)

    with {:ok, gross_monthly_income} <- gross_monthly_income(customer) do
      existing_obligations = existing_monthly_obligations(scope, customer.id)

      %{monthly_payment: proposed_installment} =
        InterestCalculator.calculate(%{
          amount: application.requested_amount,
          interest_rate: product.interest_rate,
          term_months: application.requested_term_months
        })

      ratio =
        existing_obligations
        |> Decimal.add(proposed_installment)
        |> Decimal.div(gross_monthly_income)
        |> Decimal.mult(Decimal.new("100"))

      if Decimal.compare(ratio, product.max_debt_to_income_percent) == :gt do
        {:error, :affordability_exceeded}
      else
        :ok
      end
    end
  end

  # Business customers' KYC data never captured a monthly income figure
  # directly (Step 7) — annual_turnover / 12 is the only proxy on file.
  defp gross_monthly_income(%Customer{customer_type: "individual", monthly_income: income})
       when not is_nil(income),
       do: {:ok, income}

  defp gross_monthly_income(%Customer{customer_type: "business", annual_turnover: turnover})
       when not is_nil(turnover),
       do: {:ok, Decimal.div(turnover, 12)}

  defp gross_monthly_income(%Customer{}), do: {:error, :income_data_missing}

  # Lending.get_upcoming_installments/2 returns every not-yet-paid
  # installment across all the customer's accounts, due_date ascending
  # — uniq_by keeps the first (soonest-due) one per account, which is
  # that account's fixed monthly PMT amount (only the final
  # installment's rounding differs, never worth chasing here).
  defp existing_monthly_obligations(scope, customer_id) do
    scope
    |> Lending.get_upcoming_installments(customer_id)
    |> Enum.uniq_by(& &1.loan_account_id)
    |> Enum.reduce(Decimal.new("0"), fn installment, acc ->
      Decimal.add(acc, installment.scheduled_amount)
    end)
  end
end
