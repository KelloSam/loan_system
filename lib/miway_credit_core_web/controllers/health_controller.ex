defmodule MiwayCreditCoreWeb.HealthController do
  use MiwayCreditCoreWeb, :controller

  @doc "Unauthenticated liveness endpoint for load balancers / uptime monitors — confirms the BEAM process is up and Phoenix is routing. No DB dependency by design."
  def show(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
