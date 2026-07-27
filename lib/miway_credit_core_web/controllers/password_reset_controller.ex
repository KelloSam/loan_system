defmodule MiwayCreditCoreWeb.PasswordResetController do
  use MiwayCreditCoreWeb, :controller

  alias MiwayCreditCore.{Accounts, AuditLogs}

  # ---------------------------------------------------------------------------
  # Step 1 — request a reset link
  # ---------------------------------------------------------------------------

  def new(conn, _params) do
    conn
    |> put_layout(html: false)
    |> render(:new)
  end

  def create(conn, %{"password_reset" => %{"email" => email}}) do
    Accounts.request_password_reset(email, &url(~p"/password-reset/#{&1}"))

    AuditLogs.log("password_reset_requested",
      actor_email: email,
      ip_address: get_ip(conn),
      metadata: %{attempted_email: email}
    )

    conn
    |> put_flash(:info, "If an account exists for that email, password-reset instructions have been sent.")
    |> redirect(to: ~p"/login")
  end

  # ---------------------------------------------------------------------------
  # Step 2 — set a new password
  # ---------------------------------------------------------------------------

  def edit(conn, %{"token" => token}) do
    if Accounts.get_valid_reset_token(token) do
      conn
      |> put_layout(html: false)
      |> render(:edit, token: token, changeset: nil)
    else
      conn
      |> put_flash(:error, "That reset link is invalid or has expired. Request a new one.")
      |> redirect(to: ~p"/password-reset")
    end
  end

  def update(conn, %{"token" => token, "password_reset" => %{"password" => password}}) do
    case Accounts.get_valid_reset_token(token) do
      nil ->
        conn
        |> put_flash(:error, "That reset link is invalid or has expired. Request a new one.")
        |> redirect(to: ~p"/password-reset")

      reset_token ->
        case Accounts.reset_password(reset_token, %{password: password}) do
          {:ok, user} ->
            AuditLogs.log("password_reset_completed",
              actor_id: user.id,
              actor_email: user.email,
              ip_address: get_ip(conn)
            )

            conn
            |> put_flash(:info, "Your password has been reset. Please sign in.")
            |> redirect(to: ~p"/login")

          {:error, changeset} ->
            conn
            |> put_layout(html: false)
            |> put_flash(:error, "Couldn't reset your password.")
            |> render(:edit, token: token, changeset: changeset)
        end
    end
  end

  defp get_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end
