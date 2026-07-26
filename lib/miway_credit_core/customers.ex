defmodule MiwayCreditCore.Customers do
  import Ecto.Query
  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.Customers.Customer

  @doc """
  Returns a paginated list of customers ordered by name.
  Accepts `page:` and `per_page:` opts (defaults: 1, 50).
  """
  def list_customers(opts \\ []) do
    page     = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 50)
    offset   = (page - 1) * per_page

    Customer
    |> order_by([c], asc: c.name)
    |> limit(^per_page)
    |> offset(^offset)
    |> Repo.all()
  end

  def get_customer!(id) do
    Repo.get!(Customer, id)
  end

  def create_customer(attrs \\ %{}) do
    %Customer{}
    |> Customer.changeset(attrs)
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

  def get_customer_by_email(email) do
    Repo.get_by(Customer, email: email)
  end

  def get_customer_by_phone(phone) do
    Repo.get_by(Customer, phone: phone)
  end

  def get_customer_by_id_number(id_number) do
    Repo.get_by(Customer, id_number: id_number)
  end

  def count_customers, do: Repo.aggregate(Customer, :count)
end
