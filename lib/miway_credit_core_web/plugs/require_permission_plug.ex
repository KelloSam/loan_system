defmodule MiwayCreditCoreWeb.Plugs.RequirePermissionPlug do
  @moduledoc """
  Server-side permission enforcement — declared per action in each
  controller:

      plug MiwayCreditCoreWeb.Plugs.RequirePermissionPlug, "applications.approve" when action == :approve

  Hiding a menu item is a UI nicety; this is the check that can't be
  bypassed by hitting the URL directly. Returns a real 403, not a
  redirect — the requester is properly authenticated, they just lack
  this one permission, so sending them back to /login would be wrong.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias MiwayCreditCore.Authorization

  def init(permission_key), do: permission_key

  def call(conn, permission_key) do
    if Authorization.authorized?(conn.assigns.current_scope, permission_key) do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> put_view(MiwayCreditCoreWeb.ErrorHTML)
      |> render("403.html")
      |> halt()
    end
  end
end
