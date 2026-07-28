defmodule MiwayCreditCoreWeb.ProductController do
  use MiwayCreditCoreWeb, :controller

  alias MiwayCreditCore.{Products, AuditLogs}
  alias MiwayCreditCore.Products.LoanProduct
  alias MiwayCreditCoreWeb.Plugs.RequirePermissionPlug

  plug RequirePermissionPlug, "products.view" when action == :index
  plug RequirePermissionPlug, "products.manage" when action in [:new, :create, :edit, :update, :retire, :activate]

  def index(conn, _params) do
    products = Products.list_products(conn.assigns.current_scope)
    render(conn, :index, products: products)
  end

  def new(conn, _params) do
    changeset = LoanProduct.changeset(%LoanProduct{}, %{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"product" => product_params}) do
    case Products.create_product(conn.assigns.current_scope, product_params) do
      {:ok, product} ->
        AuditLogs.log("product_created",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "product",
          target_id: product.id,
          ip_address: get_ip(conn),
          metadata: %{name: product.name, interest_rate: product.interest_rate}
        )

        conn
        |> put_flash(:info, "Product created.")
        |> redirect(to: ~p"/admin/products")

      {:error, changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end

  def edit(conn, %{"id" => id}) do
    product = Products.get_product!(conn.assigns.current_scope, id)
    changeset = LoanProduct.changeset(product, %{})
    render(conn, :edit, product: product, changeset: changeset)
  end

  def update(conn, %{"id" => id, "product" => product_params}) do
    product = Products.get_product!(conn.assigns.current_scope, id)

    case Products.update_product(product, product_params) do
      {:ok, product} ->
        AuditLogs.log("product_updated",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "product",
          target_id: product.id,
          ip_address: get_ip(conn),
          metadata: %{name: product.name}
        )

        conn
        |> put_flash(:info, "Product updated.")
        |> redirect(to: ~p"/admin/products")

      {:error, changeset} ->
        render(conn, :edit, product: product, changeset: changeset)
    end
  end

  def retire(conn, %{"id" => id}) do
    product = Products.get_product!(conn.assigns.current_scope, id)
    {:ok, product} = Products.retire_product(product)

    AuditLogs.log("product_retired",
      actor_id: conn.assigns.current_user.id,
      actor_email: conn.assigns.current_user.email,
      target_type: "product",
      target_id: product.id,
      ip_address: get_ip(conn)
    )

    conn
    |> put_flash(:info, "Product retired — no longer selectable for new applications.")
    |> redirect(to: ~p"/admin/products")
  end

  def activate(conn, %{"id" => id}) do
    product = Products.get_product!(conn.assigns.current_scope, id)
    {:ok, product} = Products.activate_product(product)

    AuditLogs.log("product_activated",
      actor_id: conn.assigns.current_user.id,
      actor_email: conn.assigns.current_user.email,
      target_type: "product",
      target_id: product.id,
      ip_address: get_ip(conn)
    )

    conn
    |> put_flash(:info, "Product reactivated.")
    |> redirect(to: ~p"/admin/products")
  end

  defp get_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end
