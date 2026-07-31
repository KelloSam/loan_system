defmodule MiwayCreditCoreWeb.Plugs.AuthPlug do
  import Plug.Conn
  import Phoenix.Controller

  alias MiwayCreditCore.{Accounts, Organisations}
  alias MiwayCreditCore.Accounts.Scope

  def init(opts), do: opts

  @doc """
  Authenticates the request from the session and assigns the current
  identity plus its organisation Scope.

  Reloads the User fresh from the DB on every request (rather than
  trusting session-cached fields) so a suspended account or an
  invalidated session (see below) takes effect immediately, not just
  at next login.

  Assigns:
    :current_user            — the %User{} struct
    :current_staff_member    — %StaffMember{} if this login is staff, else nil
    :current_customer        — the linked %Customer{} if this login is a
                                customer-portal account, else nil
    :current_scope            — %Scope{} — see Accounts.Scope. Every
                                context call that touches
                                organisation-owned data takes this.

  Sessions are signed/encrypted client-side cookies with no
  server-side store to revoke from, so "logging out everywhere" (used
  by password reset) works by comparing the session's `authenticated_at`
  timestamp against `user.sessions_invalidated_at` — a session issued
  before the last invalidation is rejected here.
  """
  def call(conn, _opts) do
    with user_id when not is_nil(user_id) <- get_session(conn, :user_id),
         authenticated_at when not is_nil(authenticated_at) <-
           get_session(conn, :authenticated_at),
         %Accounts.User{} = user <- Accounts.get_user!(user_id),
         :ok <- check_status(user),
         :ok <- check_session_not_invalidated(user, authenticated_at),
         {:ok, staff_member, customer, scope} <- build_scope(user) do
      conn
      |> assign(:current_user, user)
      |> assign(:current_staff_member, staff_member)
      |> assign(:current_customer, customer)
      |> assign(:current_scope, scope)
    else
      {:error, message} ->
        conn
        |> put_flash(:error, message)
        |> redirect(to: "/login")
        |> halt()

      _ ->
        conn
        |> put_flash(:error, "You must log in to access this page")
        |> redirect(to: "/login")
        |> halt()
    end
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_flash(:error, "You must log in to access this page")
      |> redirect(to: "/login")
      |> halt()
  end

  defp build_scope(user) do
    case Accounts.get_staff_member(user.id) do
      %Accounts.StaffMember{role: "platform_administrator"} = staff_member ->
        {:ok, staff_member, nil, Scope.for_platform_administrator(user, staff_member)}

      %Accounts.StaffMember{} = staff_member ->
        case Organisations.get_active_membership_for_staff_member(staff_member.id) do
          nil ->
            {:error, "Your account isn't linked to an organisation. Contact your administrator."}

          membership ->
            {:ok, staff_member, nil,
             Scope.for_staff_member(user, staff_member, membership.organisation_id)}
        end

      nil ->
        case Accounts.get_customer_user(user.id) do
          nil ->
            {:ok, nil, nil, nil}

          customer_user ->
            {:ok, nil, customer_user.customer, Scope.for_customer(user, customer_user.customer)}
        end
    end
  end

  defp check_status(%Accounts.User{status: "active"}), do: :ok
  defp check_status(%Accounts.User{}), do: {:error, "Your account has been suspended."}

  defp check_session_not_invalidated(
         %Accounts.User{sessions_invalidated_at: nil},
         _authenticated_at
       ),
       do: :ok

  defp check_session_not_invalidated(
         %Accounts.User{sessions_invalidated_at: invalidated_at},
         authenticated_at
       ) do
    if NaiveDateTime.compare(authenticated_at, invalidated_at) == :lt do
      {:error, "Your session has expired. Please log in again."}
    else
      :ok
    end
  end
end
