defmodule MiwayCreditCore.Loans.InterestCalculator do
  @moduledoc false

  @doc """
  Calculates compound interest details for a loan using monthly compounding.

  Formula: PMT = P × r / (1 - (1+r)^-n)
    where r = annual_rate / 1200, n = term_months

  Returns a map with:
    - :monthly_payment     – fixed monthly instalment
    - :total_repayment     – sum of all instalments
    - :total_interest      – total_repayment minus principal
    - :compound_lump_sum   – what would be owed if no payments were made (A = P(1+r)^n)
    - :effective_annual_rate – (1 + r)^12 - 1, expressed as a percentage
  """
  def calculate(%{amount: principal, interest_rate: annual_rate, term_months: n})
      when is_struct(principal, Decimal) and is_struct(annual_rate, Decimal) and is_integer(n) and
             n > 0 do
    p = Decimal.to_float(principal)
    r = Decimal.to_float(annual_rate) / 1200.0

    if r == 0.0 do
      mp = p / n

      %{
        monthly_payment: to_decimal(mp),
        total_repayment: principal,
        total_interest: Decimal.new("0.00"),
        compound_lump_sum: principal,
        effective_annual_rate: Decimal.new("0.00")
      }
    else
      factor = :math.pow(1 + r, n)
      monthly_payment = p * r * factor / (factor - 1)
      total_repayment = monthly_payment * n
      total_interest = total_repayment - p
      compound_lump_sum = p * factor
      # Effective Annual Rate: (1+r)^12 - 1 as percentage
      ear = (:math.pow(1 + r, 12) - 1) * 100

      %{
        monthly_payment: to_decimal(monthly_payment),
        total_repayment: to_decimal(total_repayment),
        total_interest: to_decimal(total_interest),
        compound_lump_sum: to_decimal(compound_lump_sum),
        effective_annual_rate: to_decimal(ear)
      }
    end
  end

  defp to_decimal(float) when is_float(float) do
    float
    |> Float.round(2)
    |> Decimal.from_float()
  end
end
