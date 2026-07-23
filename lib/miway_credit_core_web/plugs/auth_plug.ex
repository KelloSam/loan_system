defmodule MiwayCreditCoreWeb.Plugs.AuthPlug do
  import Plug.Conn
  import Phoenix.Controller

  alias MiwayCreditCore.Accounts.User

  def init(opts), do: opts

  @doc """
  Authenticates the request from the session.

  Builds a %User{} struct from session-cached fields (id, role, email)
  to avoid a DB query on every request. Role and email are written to
  the session at login (SessionController.create) and are refreshed
  whenever the user logs in again.

  If the session is missing, redirects to /login.
  """
  def call(conn, _opts) do
    with user_id when not is_nil(user_id) <- get_session(conn, :user_id),
         role  when not is_nil(role)    <- get_session(conn, :user_role),
         email when not is_nil(email)   <- get_session(conn, :user_email) do
      current_user = %User{id: user_id, role: role, email: email}
      assign(conn, :current_user, current_user)
    else
      _ ->
        conn
        |> put_flash(:error, "You must log in to access this page")
        |> redirect(to: "/login")
        |> halt()
    end
  end
end
