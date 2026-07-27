defmodule MiwayCreditCoreWeb.Plugs.EnsureCustomerPlug do
  @moduledoc "Gates the /client routes to logins linked to a Customer via CustomerUser."

  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.assigns[:current_customer] do
      conn
    else
      conn
      |> put_flash(:error, "You are not authorized to access this page")
      |> redirect(to: "/login")
      |> halt()
    end
  end
end
