defmodule LoanSystem.Clients do
  import Ecto.Query
  alias LoanSystem.Repo
  alias LoanSystem.Clients.Client

  @doc """
  Returns a paginated list of clients ordered by name.
  Accepts `page:` and `per_page:` opts (defaults: 1, 50).
  """
  def list_clients(opts \ []) do
    page     = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 50)
    offset   = (page - 1) * per_page

    Client
    |> order_by([c], asc: c.name)
    |> limit(^per_page)
    |> offset(^offset)
    |> Repo.all()
  end

  def get_client!(id) do
    Repo.get!(Client, id)
  end

  def create_client(attrs \\ %{}) do
    %Client{}
    |> Client.changeset(attrs)
    |> Repo.insert()
  end

  def update_client(%Client{} = client, attrs) do
    client
    |> Client.changeset(attrs)
    |> Repo.update()
  end

  def delete_client(%Client{} = client) do
    Repo.delete(client)
  end

  def get_client_by_email(email) do
    Repo.get_by(Client, email: email)
  end

  def get_client_by_phone(phone) do
    Repo.get_by(Client, phone: phone)
  end

  def get_client_by_id_number(id_number) do
    Repo.get_by(Client, id_number: id_number)
  end
end
