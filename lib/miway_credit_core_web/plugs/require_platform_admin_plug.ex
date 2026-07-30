defmodule MiwayCreditCoreWeb.Plugs.RequirePlatformAdminPlug do
  @moduledoc """
  Gates a page to platform administrators only — for genuinely
  platform-wide (not org-scoped) data, like MiwayCreditCore.Monitoring's
  scheduler/pool/disk/scanner health. There's no permission-catalog way
  to express "platform_administrator but not organisation_administrator"
  (Authorization.authorized?/2's `:all`-scope clause is unconditional),
  so this checks the scope directly instead — same 403 shape as
  RequirePermissionPlug.
  """

  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.assigns.current_scope.organisation_id == :all do
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
