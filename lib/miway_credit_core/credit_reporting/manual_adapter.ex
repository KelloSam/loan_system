defmodule MiwayCreditCore.CreditReporting.ManualAdapter do
  @moduledoc """
  The only adapter built so far — staff check a bureau outside the
  system, then key in what they found. See `ProviderAdapter` in
  `docs/architecture/context_boundaries.md` for what a real automated
  integration would add later, behind the same public shape.
  """

  alias MiwayCreditCore.Customers
  alias MiwayCreditCore.Customers.Customer
  alias MiwayCreditCore.CreditReporting.CreditReport
  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.Accounts.Scope

  @doc """
  Records a CRB check result. Refuses with `{:error, :consent_required}`
  when the customer has no active `credit_check` consent on file
  (`MiwayCreditCore.Customers.has_active_consent?/3`) — a CRB pull is
  never recorded without consent, even after the fact.
  organisation_id/customer_id always derive from `customer`, never
  from attrs.
  """
  def record_report(%Scope{} = scope, %Customer{} = customer, attrs, requested_by_id) do
    if Customers.has_active_consent?(scope, customer.id, "credit_check") do
      attrs =
        attrs
        |> stringify_keys()
        |> Map.put("organisation_id", customer.organisation_id)
        |> Map.put("customer_id", customer.id)
        |> Map.put("requested_by_id", requested_by_id)
        |> Map.put_new("provider", "manual")

      %CreditReport{}
      |> CreditReport.changeset(attrs)
      |> Repo.insert()
    else
      {:error, :consent_required}
    end
  end

  defp stringify_keys(attrs), do: Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
end
