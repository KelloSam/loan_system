defmodule MiwayCreditCoreWeb.CustomerController do
  use MiwayCreditCoreWeb, :controller

  alias MiwayCreditCore.{Customers, Loans, AuditLogs}
  alias MiwayCreditCore.Customers.Customer

  def index(conn, _params) do
    customers = Customers.list_customers()
    render(conn, :index, customers: customers)
  end

  def show(conn, %{"id" => id}) do
    customer = Customers.get_customer!(id)
    applications = Loans.get_applications_for_customer(customer.id)
    render(conn, :show, customer: customer, applications: applications)
  end

  def new(conn, _params) do
    changeset = Customer.changeset(%Customer{}, %{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"customer" => customer_params}) do
    case Customers.create_customer(customer_params) do
      {:ok, customer} ->
        AuditLogs.log("customer_created",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "customer",
          target_id: customer.id,
          ip_address: get_ip(conn),
          metadata: %{name: customer.name, phone: customer.phone}
        )

        conn
        |> put_flash(:info, "Customer created successfully.")
        |> redirect(to: ~p"/admin/customers/#{customer}")

      {:error, changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end

  def edit(conn, %{"id" => id}) do
    customer = Customers.get_customer!(id)
    changeset = Customer.changeset(customer, %{})
    render(conn, :edit, customer: customer, changeset: changeset)
  end

  def update(conn, %{"id" => id, "customer" => customer_params}) do
    customer = Customers.get_customer!(id)

    case Customers.update_customer(customer, customer_params) do
      {:ok, customer} ->
        AuditLogs.log("customer_updated",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "customer",
          target_id: customer.id,
          ip_address: get_ip(conn),
          metadata: %{name: customer.name}
        )

        conn
        |> put_flash(:info, "Customer updated successfully.")
        |> redirect(to: ~p"/admin/customers/#{customer}")

      {:error, changeset} ->
        render(conn, :edit, customer: customer, changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    customer = Customers.get_customer!(id)

    case Customers.delete_customer(customer) do
      {:ok, _} ->
        AuditLogs.log("customer_deleted",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "customer",
          target_id: customer.id,
          ip_address: get_ip(conn),
          metadata: %{name: customer.name}
        )

        conn
        |> put_flash(:info, "Customer deleted.")
        |> redirect(to: ~p"/admin/customers")

      {:error, _} ->
        conn
        |> put_flash(:error, "Cannot delete this customer — they have existing loans.")
        |> redirect(to: ~p"/admin/customers/#{id}")
    end
  end

  defp get_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end
