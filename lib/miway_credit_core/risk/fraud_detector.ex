defmodule MiwayCreditCore.Risk.FraudDetector do
  @moduledoc """
  Scores a loan application across six risk signals and returns a risk level.
  Internal to the Risk context — callers outside Risk should go through
  `MiwayCreditCore.Risk.evaluate/3`, not this module directly.

  Thresholds
    0–25  → "low"    proceed normally
    26–55 → "medium" flag for closer review
    56+   → "high"   urgent review required before approval

  Usage
    # Before saving a new application (exclude_application_id is nil):
    {level, score, signals} = FraudDetector.evaluate(customer_id, amount)

    # When re-evaluating an existing application (exclude it from averages):
    {level, score, signals} = FraudDetector.evaluate(customer_id, amount, application_id)
  """

  import Ecto.Query
  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.Applications.LoanApplication
  alias MiwayCreditCore.Customers.Customer

  @medium_threshold 26
  @high_threshold   56

  @doc """
  Evaluates a loan application and returns {risk_level, score, signal_texts}.
  Pass `exclude_application_id` when the application already exists in the
  DB so it is not counted in its own historical averages.
  """
  def evaluate(customer_id, amount, exclude_application_id \\ nil) do
    d_amount = to_decimal(amount)

    signals =
      [
        signal_new_customer(customer_id),
        signal_no_repayment_history(customer_id, exclude_application_id),
        signal_large_first_loan(customer_id, d_amount, exclude_application_id),
        signal_amount_vs_average(customer_id, d_amount, exclude_application_id),
        signal_recent_rejection(customer_id),
        signal_round_amount(d_amount)
      ]
      |> Enum.reject(&is_nil/1)

    score     = signals |> Enum.map(&elem(&1, 0)) |> Enum.sum()
    texts     = signals |> Enum.map(&elem(&1, 1))
    risk_level = classify(score)

    {risk_level, score, texts}
  end

  # ---------------------------------------------------------------------------
  # Classification
  # ---------------------------------------------------------------------------

  defp classify(score) when score < @medium_threshold, do: "low"
  defp classify(score) when score < @high_threshold,   do: "medium"
  defp classify(_score),                               do: "high"

  # ---------------------------------------------------------------------------
  # Individual signals — each returns {points, text} or nil
  # ---------------------------------------------------------------------------

  # +20 — account created less than 7 days ago
  defp signal_new_customer(nil), do: nil
  defp signal_new_customer(customer_id) do
    cutoff = NaiveDateTime.utc_now() |> NaiveDateTime.add(-7 * 24 * 60 * 60, :second)

    new? =
      from(c in Customer,
        where: c.id == ^customer_id and c.inserted_at >= ^cutoff,
        select: count(c.id)
      )
      |> Repo.one()
      |> Kernel.>(0)

    if new?, do: {20, "Customer account is less than 7 days old"}, else: nil
  end

  # +15 — no approved or completed loans on record
  defp signal_no_repayment_history(nil, _exclude), do: nil
  defp signal_no_repayment_history(customer_id, exclude_id) do
    if prior_successful_count(customer_id, exclude_id) == 0 do
      {15, "No repayment history on record"}
    else
      nil
    end
  end

  # +25 — first loan AND amount exceeds 5 000 ZMW
  defp signal_large_first_loan(nil, _amount, _exclude), do: nil
  defp signal_large_first_loan(customer_id, amount, exclude_id) do
    first? = prior_successful_count(customer_id, exclude_id) == 0
    large? = Decimal.compare(amount, Decimal.new("5000")) == :gt

    if first? and large? do
      {25, "First loan request of ZMW #{amount} with no established history"}
    else
      nil
    end
  end

  # +20 — amount is more than 3× customer's historical average
  defp signal_amount_vs_average(nil, _amount, _exclude), do: nil
  defp signal_amount_vs_average(customer_id, amount, exclude_id) do
    case avg_prior_loans(customer_id, exclude_id) do
      nil -> nil
      prior_avg ->
        threshold = Decimal.mult(prior_avg, Decimal.new("3"))

        if Decimal.compare(amount, threshold) == :gt do
          formatted = prior_avg |> Decimal.round(2) |> Decimal.to_string()
          {20, "Amount ZMW #{amount} exceeds 3× the customer's average of ZMW #{formatted}"}
        else
          nil
        end
    end
  end

  # +25 — a rejection within the last 90 days (Phase 1 blocks < 30 days;
  # this catches the 30–90 day window after that hard block lifts)
  defp signal_recent_rejection(nil), do: nil
  defp signal_recent_rejection(customer_id) do
    cutoff =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.add(-90 * 24 * 60 * 60, :second)
      |> NaiveDateTime.truncate(:second)

    count =
      from(la in LoanApplication,
        where:
          la.customer_id == ^customer_id and
            la.status == "rejected" and
            la.updated_at >= ^cutoff,
        select: count(la.id)
      )
      |> Repo.one()

    if count > 0, do: {25, "Customer had a loan rejected within the last 90 days"}, else: nil
  end

  # +10 — amount is a suspiciously round number (divisible by 1 000)
  defp signal_round_amount(amount) do
    int_part =
      amount
      |> Decimal.to_string()
      |> String.split(".")
      |> hd()
      |> String.to_integer()

    if int_part > 0 and rem(int_part, 1000) == 0 do
      {10, "Loan amount ZMW #{amount} is a round figure — common in fraudulent applications"}
    else
      nil
    end
  end

  # ---------------------------------------------------------------------------
  # DB helpers
  # ---------------------------------------------------------------------------

  defp prior_successful_count(customer_id, nil) do
    from(la in LoanApplication,
      where: la.customer_id == ^customer_id and la.status == "approved",
      select: count(la.id)
    )
    |> Repo.one()
  end

  defp prior_successful_count(customer_id, exclude_id) do
    from(la in LoanApplication,
      where:
        la.customer_id == ^customer_id and
          la.status == "approved" and
          la.id != ^exclude_id,
      select: count(la.id)
    )
    |> Repo.one()
  end

  defp avg_prior_loans(customer_id, nil) do
    from(la in LoanApplication,
      where: la.customer_id == ^customer_id and la.status == "approved",
      select: avg(la.requested_amount)
    )
    |> Repo.one()
  end

  defp avg_prior_loans(customer_id, exclude_id) do
    from(la in LoanApplication,
      where:
        la.customer_id == ^customer_id and
          la.status == "approved" and
          la.id != ^exclude_id,
      select: avg(la.requested_amount)
    )
    |> Repo.one()
  end

  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(v), do: Decimal.new(to_string(v))
end
