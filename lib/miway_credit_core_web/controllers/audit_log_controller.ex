defmodule MiwayCreditCoreWeb.AuditLogController do
  use MiwayCreditCoreWeb, :controller

  alias MiwayCreditCore.AuditLogs
  alias MiwayCreditCoreWeb.Plugs.RequirePermissionPlug

  plug RequirePermissionPlug, "audit.view" when action == :index

  def index(conn, _params) do
    logs = AuditLogs.list_recent(100)
    render(conn, :index, logs: logs)
  end
end
