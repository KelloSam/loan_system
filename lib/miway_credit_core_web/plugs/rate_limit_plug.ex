defmodule MiwayCreditCoreWeb.Plugs.RateLimitPlug do
  use PlugAttack

  # Allow 10 POST /login attempts per IP per minute.
  # The per-account lockout in Accounts.authenticate_user/2 guards
  # individual accounts; this guards against credential-stuffing across
  # many accounts from a single source.
  rule "login by ip", conn do
    if conn.method == "POST" and conn.request_path == "/login" do
      throttle conn.remote_ip,
        period: 60_000,
        limit: 10,
        storage: {PlugAttack.Storage.Ets, MiwayCreditCoreWeb.RateLimitStorage}
    end
  end

  def allow_action(conn, {:throttle, data}, _opts) do
    conn
    |> Plug.Conn.put_resp_header("x-ratelimit-limit", to_string(data[:limit]))
    |> Plug.Conn.put_resp_header("x-ratelimit-remaining", to_string(data[:remaining]))
    |> Plug.Conn.put_resp_header("x-ratelimit-reset", to_string(data[:reset]))
  end

  def block_action(conn, {:throttle, _data}, _opts) do
    conn
    |> Phoenix.Controller.put_flash(:error, "Too many login attempts. Please wait a minute and try again.")
    |> Phoenix.Controller.redirect(to: "/login")
    |> Plug.Conn.halt()
  end
end
