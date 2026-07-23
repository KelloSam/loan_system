defmodule MiwayCreditCoreWeb.SessionController do
  use MiwayCreditCoreWeb, :controller

  alias MiwayCreditCore.Accounts
  alias MiwayCreditCore.AuditLogs

  def new(conn, _params) do
    conn
    |> put_layout(html: false)
    |> render(:new)
  end

  def create(conn, %{"session" => %{"email" => email, "password" => password}}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        AuditLogs.log("login_success",
          actor_id: user.id,
          actor_email: user.email,
          ip_address: get_ip(conn)
        )

        conn = configure_session(conn, renew: true)

        if user.totp_enabled do
          # Password OK but 2FA required — hold the user in a pending state
          conn
          |> put_session(:pending_2fa_user_id, user.id)
          |> redirect(to: ~p"/login/verify")
        else
          conn
          |> put_session(:user_id, user.id)
          |> put_session(:user_role, user.role)
          |> put_session(:user_email, user.email)
          |> put_flash(:info, "Welcome back!")
          |> redirect(to: user_redirect_path(user))
        end

      {:error, {:account_locked, locked_until}} ->
        remaining = max(1, div(NaiveDateTime.diff(locked_until, NaiveDateTime.utc_now(), :second), 60))

        AuditLogs.log("login_blocked_lockout",
          actor_email: email,
          ip_address: get_ip(conn),
          metadata: %{attempted_email: email}
        )

        conn
        |> put_layout(html: false)
        |> put_flash(:error, "Account locked after too many failed attempts. Try again in #{remaining} minute(s).")
        |> render(:new)

      {:error, :invalid_credentials} ->
        AuditLogs.log("login_failure",
          actor_email: email,
          ip_address: get_ip(conn),
          metadata: %{attempted_email: email}
        )

        conn
        |> put_layout(html: false)
        |> put_flash(:error, "Invalid email or password.")
        |> render(:new)
    end
  end

  def delete(conn, _params) do
    AuditLogs.log("logout",
      actor_id: get_session(conn, :user_id),
      actor_email: get_session(conn, :user_email),
      ip_address: get_ip(conn)
    )

    conn
    |> clear_session()
    |> configure_session(drop: true)
    |> put_flash(:info, "Logged out successfully.")
    |> redirect(to: ~p"/")
  end

  defp user_redirect_path(%{role: "admin"}), do: ~p"/admin/dashboard"
  defp user_redirect_path(_user), do: ~p"/client/dashboard"

  defp get_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end
