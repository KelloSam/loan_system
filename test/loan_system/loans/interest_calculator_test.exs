defmodule LoanSystem.Loans.InterestCalculatorTest do
  use ExUnit.Case, async: true

  alias LoanSystem.Loans.InterestCalculator

  describe "calculate/1" do
    test "computes compound interest for a standard loan" do
      loan = %{amount: Decimal.new("10000"), interest_rate: Decimal.new("12.0"), term_months: 12}
      result = InterestCalculator.calculate(loan)

      # PMT = P*r/(1-(1+r)^-n), r = 0.01, n = 12 -> ~888.49
      assert Decimal.equal?(result.monthly_payment, Decimal.new("888.49"))
      assert Decimal.compare(result.total_repayment, loan.amount) == :gt
      assert Decimal.compare(result.total_interest, Decimal.new("0")) == :gt
      assert Decimal.compare(result.compound_lump_sum, loan.amount) == :gt
      assert Decimal.compare(result.effective_annual_rate, Decimal.new("0")) == :gt
      # total_interest is total_repayment minus principal
      assert Decimal.equal?(result.total_interest, Decimal.sub(result.total_repayment, loan.amount))
    end

    test "zero-interest loans split principal evenly with no interest" do
      loan = %{amount: Decimal.new("1200"), interest_rate: Decimal.new("0"), term_months: 12}
      result = InterestCalculator.calculate(loan)

      assert Decimal.equal?(result.monthly_payment, Decimal.new("100.00"))
      assert Decimal.equal?(result.total_repayment, loan.amount)
      assert Decimal.equal?(result.total_interest, Decimal.new("0.00"))
      assert Decimal.equal?(result.compound_lump_sum, loan.amount)
      assert Decimal.equal?(result.effective_annual_rate, Decimal.new("0.00"))
    end

    test "a higher rate produces a higher monthly payment for the same principal/term" do
      low = InterestCalculator.calculate(%{amount: Decimal.new("5000"), interest_rate: Decimal.new("5.0"), term_months: 6})
      high = InterestCalculator.calculate(%{amount: Decimal.new("5000"), interest_rate: Decimal.new("20.0"), term_months: 6})

      assert Decimal.compare(high.monthly_payment, low.monthly_payment) == :gt
      assert Decimal.compare(high.effective_annual_rate, low.effective_annual_rate) == :gt
    end
  end
end
