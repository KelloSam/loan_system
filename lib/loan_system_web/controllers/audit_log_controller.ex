defmodule LoanSystemWeb.AuditLogController do
  use LoanSystemWeb, :controller

  alias LoanSystem.AuditLogs

  def index(conn, _params) do
    logs = AuditLogs.list_recent(100)
    render(conn, :index, logs: logs)
  end
end
