defmodule LoanSystemWeb.SessionController do
  use LoanSystemWeb, :controller

  alias LoanSystem.Accounts
  alias LoanSystem.AuditLogs

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

        conn
        |> configure_session(renew: true)
        |> put_session(:user_id, user.id)
        |> put_session(:user_role, user.role)
        |> put_session(:user_email, user.email)
        |> put_flash(:info, "Welcome back!")
        |> redirect(to: user_redirect_path(user))

      {:error, _reason} ->
        AuditLogs.log("login_failure",
          actor_email: email,
          ip_address: get_ip(conn),
          metadata: %{attempted_email: email}
        )

        conn
        |> put_layout(html: false)
        |> put_flash(:error, "Invalid email or password")
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
