defmodule MiwayCreditCoreWeb.HealthController do
  use MiwayCreditCoreWeb, :controller

  require Logger

  alias MiwayCreditCore.Repo

  @doc "Unauthenticated liveness endpoint for load balancers / uptime monitors — confirms the BEAM process is up and Phoenix is routing. No DB dependency by design."
  def show(conn, _params) do
    json(conn, %{status: "ok"})
  end

  @doc "Readiness endpoint — confirms Postgres is actually reachable, distinct from /up's process-only liveness check. 503 (not a crash) on failure, so a load balancer can route around this instance without it looking down entirely. Failure detail is logged server-side only; the public response stays generic to avoid leaking internal state."
  def ready(conn, _params) do
    case Repo.query("SELECT 1") do
      {:ok, _result} ->
        json(conn, %{status: "ready"})

      {:error, reason} ->
        Logger.error("Readiness check failed: #{inspect(reason)}")

        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "unavailable"})
    end
  rescue
    error ->
      Logger.error("Readiness check failed: #{inspect(error)}")

      conn
      |> put_status(:service_unavailable)
      |> json(%{status: "unavailable"})
  end
end
