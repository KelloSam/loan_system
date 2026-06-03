defmodule LoanSystemWeb.SessionController do
  use LoanSystemWeb, :controller

  alias LoanSystem.Accounts

  def new(conn, _params) do
    conn
    |> put_layout(html: false)
    |> render(:new)
  end

  def create(conn, %{"session" => %{"email" => email, "password" => password}}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        conn
        |> configure_session(renew: true)  # prevents session fixation
        |> put_session(:user_id, user.id)
        |> put_session(:user_role, user.role)
        |> put_session(:user_email, user.email)
        |> put_flash(:info, "Welcome back!")
        |> redirect(to: user_redirect_path(user))

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Invalid email or password")
        |> render(:new)
    end
  end

  def delete(conn, _params) do
    conn
    |> clear_session()  # clears all session keys, not just user_id
    |> configure_session(drop: true)
    |> put_flash(:info, "Logged out successfully.")
    |> redirect(to: ~p"/")
  end

  defp user_redirect_path(%{role: "admin"}), do: ~p"/admin/dashboard"
  defp user_redirect_path(_user), do: ~p"/client/dashboard"
end
