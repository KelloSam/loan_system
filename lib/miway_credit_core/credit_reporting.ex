defmodule MiwayCreditCore.CreditReporting do
  @moduledoc """
  The internal abstraction over credit reference bureau (CRB)
  reporting — so `Risk`/`Applications` ask `CreditReporting` for a
  customer's latest report instead of any context reaching into a
  bureau, or the `credit_reports` table, directly.

  `ManualAdapter` is the only adapter implemented (Step 10) — see
  `docs/architecture/context_boundaries.md` for the reserved
  `ProviderAdapter` shape a real automated integration would add
  later, and for why that document's original `Enquiries`/`Consents`
  plan aren't separate here: `Enquiries` collapses into
  `CreditReporting.CreditReport` (no async request/response to track
  yet — `ManualAdapter` is synchronous), and consent reuses
  `MiwayCreditCore.Customers.Consent`'s existing `credit_check` type
  rather than a second, context-local consent model.
  """

  import Ecto.Query
  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.CreditReporting.CreditReport
  alias MiwayCreditCore.Accounts.Scope

  @doc "Every CRB check on record for a customer, most recently checked first."
  def list_reports_for_customer(%Scope{} = scope, customer_id) do
    CreditReport
    |> scope_organisation(scope)
    |> where([r], r.customer_id == ^customer_id)
    |> order_by([r], desc: r.checked_at, desc: r.inserted_at)
    |> Repo.all()
  end

  @doc "The customer's most recently checked CRB report, or nil if none exists."
  def get_latest_report_for_customer(%Scope{} = scope, customer_id) do
    CreditReport
    |> scope_organisation(scope)
    |> where([r], r.customer_id == ^customer_id)
    |> order_by([r], desc: r.checked_at, desc: r.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  defp scope_organisation(query, %Scope{organisation_id: :all}), do: query
  defp scope_organisation(query, %Scope{organisation_id: organisation_id}) do
    where(query, organisation_id: ^organisation_id)
  end
end
