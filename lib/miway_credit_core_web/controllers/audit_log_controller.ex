defmodule MiwayCreditCoreWeb.AuditLogController do
  use MiwayCreditCoreWeb, :controller

  alias MiwayCreditCore.AuditLogs

  def index(conn, _params) do
    logs = AuditLogs.list_recent(100)
    render(conn, :index, logs: logs)
  end
end
