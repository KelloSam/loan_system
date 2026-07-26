defmodule MiwayCreditCore.Risk do
  @moduledoc """
  Fraud/affordability assessment for loan applications. Owns the
  scoring logic (`Risk.FraudDetector`) and is the single import site
  other contexts use (`alias MiwayCreditCore.Risk`) — `Applications`
  asks Risk for an assessment; it does not compute one itself.

  For now this returns a `{risk_level, risk_score, signals}` tuple
  that `Applications` stores directly on the `LoanApplication` as a
  current-result snapshot (`risk_level`/`risk_score` columns). A
  `risk_assessments` table with reassessment history is deliberately
  deferred — see `docs/architecture/context_boundaries.md`.
  """

  alias MiwayCreditCore.Risk.FraudDetector

  @doc """
  Evaluates a loan application and returns `{risk_level, score,
  signal_texts}`. Pass `exclude_application_id` when the application
  already exists in the DB so it is not counted in its own historical
  averages (see `MiwayCreditCore.Risk.FraudDetector.evaluate/3`).
  """
  defdelegate evaluate(customer_id, amount, exclude_application_id \\ nil), to: FraudDetector
end
