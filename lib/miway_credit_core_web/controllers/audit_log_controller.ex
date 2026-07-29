defmodule MiwayCreditCoreWeb.AuditLogController do
  use MiwayCreditCoreWeb, :controller

  alias MiwayCreditCore.AuditLogs
  alias MiwayCreditCoreWeb.Plugs.RequirePermissionPlug

  plug RequirePermissionPlug, "audit.view" when action in [:index, :export_csv]

  def index(conn, params) do
    filters = filter_params(params)
    scope = conn.assigns.current_scope

    logs =
      if Enum.empty?(filters),
        do: AuditLogs.list_recent(scope, 100),
        else: AuditLogs.list_filtered(scope, filters, 200)

    render(conn, :index, logs: logs, filters: filters, events: AuditLogs.event_names())
  end

  def export_csv(conn, params) do
    filters = filter_params(params)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="audit-log.csv"))
    |> send_resp(200, AuditLogs.audit_csv(conn.assigns.current_scope, filters))
  end

  defp filter_params(params) do
    params
    |> Map.take(["event", "actor_email", "from", "to"])
    |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
    |> Map.new()
  end
end
