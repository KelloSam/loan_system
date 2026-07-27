defmodule MiwayCreditCoreWeb.Plugs.EnsureStaffPlug do
  @moduledoc """
  Gates the /admin routes to any staff role. Fine-grained per-role
  authorization (platform admin vs. org admin vs. loan officer) is
  explicitly deferred — see docs/architecture/context_boundaries.md.
  """

  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.assigns[:current_staff_member] do
      conn
    else
      conn
      |> put_flash(:error, "You are not authorized to access this page")
      |> redirect(to: "/login")
      |> halt()
    end
  end
end
