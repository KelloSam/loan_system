defmodule MiwayCreditCoreWeb.TwoFactorController do
  use MiwayCreditCoreWeb, :controller

  alias MiwayCreditCore.{Accounts, AuditLogs}

  # ---------------------------------------------------------------------------
  # Step 2 of login — enter the authenticator code
  # ---------------------------------------------------------------------------

  def verify(conn, _params) do
    if get_session(conn, :pending_2fa_user_id) do
      conn
      |> put_layout(html: false)
      |> render(:verify)
    else
      redirect(conn, to: ~p"/login")
    end
  end

  def confirm(conn, %{"totp" => %{"code" => code}}) do
    user_id = get_session(conn, :pending_2fa_user_id)

    if is_nil(user_id) do
      redirect(conn, to: ~p"/login")
    else
      user = Accounts.get_user!(user_id)
      clean_code = String.replace(code, " ", "")

      cond do
        Accounts.account_locked?(user) ->
          locked_response(conn, user)

        Accounts.valid_totp?(user, clean_code) ->
          success_response(conn, user)

        true ->
          failure_response(conn, user)
      end
    end
  end

  defp success_response(conn, user) do
    Accounts.reset_failed_attempts(user)

    AuditLogs.log("2fa_success",
      actor_id: user.id,
      actor_email: user.email,
      ip_address: get_ip(conn)
    )

    conn
    |> delete_session(:pending_2fa_user_id)
    |> put_session(:user_id, user.id)
    |> put_session(:user_email, user.email)
    |> put_session(:authenticated_at, NaiveDateTime.utc_now())
    |> put_flash(:info, "Welcome back!")
    |> redirect(to: user_redirect_path(user))
  end

  defp failure_response(conn, user) do
    Accounts.increment_failed_attempts(user)

    AuditLogs.log("2fa_failure",
      actor_id: user.id,
      actor_email: user.email,
      ip_address: get_ip(conn)
    )

    conn
    |> put_layout(html: false)
    |> put_flash(:error, "Invalid code. Please try again.")
    |> render(:verify)
  end

  # Same wording as SessionController.create/2's lockout message — the
  # user experience should be indistinguishable regardless of whether
  # the password step or this TOTP step triggered the lock.
  defp locked_response(conn, user) do
    remaining = max(1, div(NaiveDateTime.diff(user.locked_until, NaiveDateTime.utc_now(), :second), 60))

    AuditLogs.log("2fa_blocked_lockout",
      actor_id: user.id,
      actor_email: user.email,
      ip_address: get_ip(conn)
    )

    conn
    |> put_layout(html: false)
    |> put_flash(:error, "Account locked after too many failed attempts. Try again in #{remaining} minute(s).")
    |> render(:verify)
  end

  # ---------------------------------------------------------------------------
  # 2FA settings — enable / disable (admin only, requires full session)
  # ---------------------------------------------------------------------------

  def setup(conn, _params) do
    user = Accounts.get_user!(conn.assigns.current_user.id)
    secret = Accounts.generate_totp_secret()
    uri = Accounts.totp_uri(user, secret)
    qr_svg = uri |> EQRCode.encode() |> EQRCode.svg(width: 220)
    manual_key = Base.encode32(secret, padding: false)

    conn
    |> put_session(:pending_totp_secret, Base.encode64(secret))
    |> render(:setup, user: user, qr_svg: qr_svg, manual_key: manual_key)
  end

  def enable(conn, %{"totp" => %{"code" => code}}) do
    encoded_secret = get_session(conn, :pending_totp_secret)

    if is_nil(encoded_secret) do
      conn
      |> put_flash(:error, "Session expired. Please try again.")
      |> redirect(to: ~p"/admin/settings/2fa")
    else
      secret = Base.decode64!(encoded_secret)
      user = Accounts.get_user!(conn.assigns.current_user.id)

      if Accounts.valid_totp_for_secret?(secret, String.replace(code, " ", "")) do
        {:ok, _} = Accounts.enable_totp(user, secret)

        AuditLogs.log("2fa_enabled",
          actor_id: user.id,
          actor_email: user.email,
          ip_address: get_ip(conn),
          organisation_id: scope_organisation_id(conn)
        )

        conn
        |> delete_session(:pending_totp_secret)
        |> put_flash(:info, "Two-factor authentication is now enabled on your account.")
        |> redirect(to: ~p"/admin/settings/2fa")
      else
        conn
        |> put_flash(:error, "Invalid code — make sure your authenticator clock is in sync and try again.")
        |> redirect(to: ~p"/admin/settings/2fa")
      end
    end
  end

  def disable(conn, _params) do
    user = Accounts.get_user!(conn.assigns.current_user.id)
    {:ok, _} = Accounts.disable_totp(user)

    AuditLogs.log("2fa_disabled",
      actor_id: user.id,
      actor_email: user.email,
      ip_address: get_ip(conn),
      organisation_id: scope_organisation_id(conn)
    )

    conn
    |> put_flash(:info, "Two-factor authentication has been disabled.")
    |> redirect(to: ~p"/admin/settings/2fa")
  end

  defp user_redirect_path(user) do
    if Accounts.get_staff_member(user.id), do: ~p"/admin/dashboard", else: ~p"/client/dashboard"
  end

  defp get_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()

  # These 2FA-settings actions run behind the :auth pipeline (unlike
  # verify/confirm, the login-step actions, which are genuinely
  # pre-auth), so a real scope is always assigned — except for a
  # platform administrator, whose :all scope isn't a single org.
  defp scope_organisation_id(conn) do
    case conn.assigns[:current_scope] do
      %{organisation_id: :all} -> nil
      %{organisation_id: organisation_id} -> organisation_id
      _ -> nil
    end
  end
end
