defmodule LoanSystemWeb.Plugs.EnsureRolePlug do
  import Plug.Conn
  import Phoenix.Controller

  def init(role), do: role

  def call(conn, role) do
    user = conn.assigns.current_user

    if user.role == role do
      conn
    else
      conn
      |> put_flash(:error, "You are not authorized to access this page")
      |> redirect(to: "/login")
      |> halt()
    end
  end
end
