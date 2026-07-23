defmodule MiwayCreditCore.LoansFixtures do
  @moduledoc "Test helpers for creating MiwayCreditCore.Loans entities."

  import MiwayCreditCore.ClientsFixtures

  @doc """
  Builds valid loan attrs as string keys, matching what the real
  controllers submit (MiwayCreditCore.Loans.create_loan/1 puts "risk_level"
  in with a string key internally, so mixing atom/string keys here would
  break cast/3 — keep everything string-keyed like production does).
  """
  def valid_loan_attrs(attrs \\ %{}) do
    client_id = attrs[:client_id] || attrs["client_id"] || client_fixture().id

    Enum.into(stringify_keys(attrs), %{
      "client_id" => client_id,
      # Deliberately not a round number — a round amount trips
      # FraudDetector's signal_round_amount and would make risk_level
      # unpredictable for tests that aren't about fraud scoring.
      "amount" => "1234.56",
      "interest_rate" => "12.0",
      "term_months" => "6",
      "remaining_balance" => "1234.56"
    })
  end

  def loan_fixture(attrs \\ %{}) do
    {:ok, loan} =
      attrs
      |> valid_loan_attrs()
      |> MiwayCreditCore.Loans.create_loan()

    loan
  end

  @doc "A loan_fixture/1 that's already approved."
  def approved_loan_fixture(attrs \\ %{}) do
    loan = loan_fixture(attrs)
    {:ok, approved} = MiwayCreditCore.Loans.approve_loan(loan)
    approved
  end

  def valid_payment_attrs(%MiwayCreditCore.Loans.Loan{} = loan, attrs \\ %{}) do
    Enum.into(stringify_keys(attrs), %{
      "loan_id" => loan.id,
      "amount" => "100.00",
      "payment_date" => Date.to_iso8601(Date.utc_today()),
      "status" => "paid"
    })
  end

  def payment_fixture(%MiwayCreditCore.Loans.Loan{} = loan, attrs \\ %{}) do
    {:ok, payment} =
      loan
      |> valid_payment_attrs(attrs)
      |> MiwayCreditCore.Loans.create_payment()

    payment
  end

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
