defmodule MiwayCreditCore.Products do
  @moduledoc """
  Configurable lending products — see `MiwayCreditCore.Products.LoanProduct`
  for the shape and why it's never versioned. A top-level context, not
  nested under `Applications`: a product is referenced by both
  `Applications` (which product an application requests) and `Lending`
  (which product's terms a resulting account was frozen from) — a
  shared, cross-cutting concept, not a subordinate child entity.
  """

  import Ecto.Query
  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.Products.LoanProduct
  alias MiwayCreditCore.Accounts.Scope

  @doc "All products for the caller's organisation, newest first — includes retired ones (for the management screen)."
  def list_products(%Scope{} = scope) do
    LoanProduct
    |> scope_organisation(scope)
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  @doc "Products currently selectable for a new application: active status, within their effective-date window."
  def list_available_products(%Scope{} = scope) do
    today = Date.utc_today()

    LoanProduct
    |> scope_organisation(scope)
    |> where([p], p.status == "active")
    |> where([p], p.effective_from <= ^today)
    |> where([p], is_nil(p.effective_until) or p.effective_until >= ^today)
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  def get_product!(%Scope{} = scope, id) do
    LoanProduct
    |> scope_organisation(scope)
    |> Repo.get!(id)
  end

  @doc "Creates a product under the caller's organisation. organisation_id always comes from scope, never from attrs."
  def create_product(%Scope{organisation_id: organisation_id}, _attrs) when organisation_id == :all do
    raise ArgumentError, "create_product/2 requires a concrete organisation scope, not :all"
  end

  def create_product(%Scope{organisation_id: organisation_id}, attrs) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.put("organisation_id", organisation_id)

    %LoanProduct{}
    |> LoanProduct.changeset(attrs)
    |> Repo.insert()
  end

  def update_product(%LoanProduct{} = product, attrs) do
    product
    |> LoanProduct.changeset(attrs)
    |> Repo.update()
  end

  def retire_product(%LoanProduct{} = product) do
    product
    |> LoanProduct.retire_changeset()
    |> Repo.update()
  end

  def activate_product(%LoanProduct{} = product) do
    product
    |> LoanProduct.activate_changeset()
    |> Repo.update()
  end

  defp stringify_keys(attrs), do: Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

  defp scope_organisation(query, %Scope{organisation_id: :all}), do: query
  defp scope_organisation(query, %Scope{organisation_id: organisation_id}) do
    where(query, organisation_id: ^organisation_id)
  end
end
