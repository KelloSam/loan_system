defmodule MiwayCreditCore.Customers do
  import Ecto.Query
  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.Customers.Customer
  alias MiwayCreditCore.Accounts.Scope

  @doc """
  Returns a paginated list of customers ordered by name, scoped to the
  caller's organisation. Accepts `page:` and `per_page:` opts (defaults: 1, 50).
  """
  def list_customers(%Scope{} = scope, opts \\ []) do
    page     = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 50)
    offset   = (page - 1) * per_page

    Customer
    |> scope_organisation(scope)
    |> order_by([c], asc: c.name)
    |> limit(^per_page)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc "Fetches a customer by id, scoped — a customer belonging to a different organisation raises the same NoResultsError as an unknown id."
  def get_customer!(%Scope{} = scope, id) do
    Customer
    |> scope_organisation(scope)
    |> Repo.get!(id)
  end

  @doc "Creates a customer under the caller's organisation. organisation_id always comes from scope, never from attrs, so it can't be spoofed via form tampering."
  def create_customer(%Scope{organisation_id: organisation_id}, _attrs) when organisation_id == :all do
    raise ArgumentError, "create_customer/2 requires a concrete organisation scope, not :all"
  end

  def create_customer(%Scope{organisation_id: organisation_id}, attrs) do
    # attrs may be atom-keyed (internal/seed callers) or string-keyed
    # (form params) — normalize before merging so cast/3 never sees a
    # map with mixed key types.
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    %Customer{}
    |> Customer.changeset(Map.put(attrs, "organisation_id", organisation_id))
    |> Repo.insert()
  end

  def update_customer(%Customer{} = customer, attrs) do
    customer
    |> Customer.changeset(attrs)
    |> Repo.update()
  end

  def delete_customer(%Customer{} = customer) do
    Repo.delete(customer)
  end

  @doc "Unscoped — used only by seed scripts, which run outside any request/scope context. Never call this from a controller."
  def get_customer_by_email(email) do
    Repo.get_by(Customer, email: email)
  end

  def get_customer_by_phone(phone) do
    Repo.get_by(Customer, phone: phone)
  end

  def get_customer_by_id_number(id_number) do
    Repo.get_by(Customer, id_number: id_number)
  end

  def count_customers(%Scope{} = scope) do
    Customer
    |> scope_organisation(scope)
    |> Repo.aggregate(:count)
  end

  defp scope_organisation(query, %Scope{organisation_id: :all}), do: query
  defp scope_organisation(query, %Scope{organisation_id: organisation_id}) do
    where(query, organisation_id: ^organisation_id)
  end
end
