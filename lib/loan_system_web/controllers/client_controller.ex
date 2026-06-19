defmodule LoanSystemWeb.ClientController do
  use LoanSystemWeb, :controller

  alias LoanSystem.{Clients, Loans, AuditLogs}
  alias LoanSystem.Clients.Client

  def index(conn, _params) do
    clients = Clients.list_clients()
    render(conn, :index, clients: clients)
  end

  def show(conn, %{"id" => id}) do
    client = Clients.get_client!(id)
    loans = Loans.get_loans_for_client(client.id)
    render(conn, :show, client: client, loans: loans)
  end

  def new(conn, _params) do
    changeset = Client.changeset(%Client{}, %{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"client" => client_params}) do
    case Clients.create_client(client_params) do
      {:ok, client} ->
        AuditLogs.log("client_created",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "client",
          target_id: client.id,
          ip_address: get_ip(conn),
          metadata: %{name: client.name, phone: client.phone}
        )

        conn
        |> put_flash(:info, "Client created successfully.")
        |> redirect(to: ~p"/admin/clients/#{client}")

      {:error, changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end

  def edit(conn, %{"id" => id}) do
    client = Clients.get_client!(id)
    changeset = Client.changeset(client, %{})
    render(conn, :edit, client: client, changeset: changeset)
  end

  def update(conn, %{"id" => id, "client" => client_params}) do
    client = Clients.get_client!(id)

    case Clients.update_client(client, client_params) do
      {:ok, client} ->
        AuditLogs.log("client_updated",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "client",
          target_id: client.id,
          ip_address: get_ip(conn),
          metadata: %{name: client.name}
        )

        conn
        |> put_flash(:info, "Client updated successfully.")
        |> redirect(to: ~p"/admin/clients/#{client}")

      {:error, changeset} ->
        render(conn, :edit, client: client, changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    client = Clients.get_client!(id)

    case Clients.delete_client(client) do
      {:ok, _} ->
        AuditLogs.log("client_deleted",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "client",
          target_id: client.id,
          ip_address: get_ip(conn),
          metadata: %{name: client.name}
        )

        conn
        |> put_flash(:info, "Client deleted.")
        |> redirect(to: ~p"/admin/clients")

      {:error, _} ->
        conn
        |> put_flash(:error, "Cannot delete this client — they have existing loans.")
        |> redirect(to: ~p"/admin/clients/#{id}")
    end
  end

  defp get_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end
