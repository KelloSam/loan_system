defmodule MiwayCreditCoreWeb.BranchController do
  use MiwayCreditCoreWeb, :controller

  alias MiwayCreditCore.{Organisations, AuditLogs}
  alias MiwayCreditCore.Organisations.Branch
  alias MiwayCreditCoreWeb.Plugs.RequirePermissionPlug

  plug RequirePermissionPlug, "branches.view" when action == :index
  plug RequirePermissionPlug, "branches.manage" when action in [:new, :create, :edit, :update]

  def index(conn, _params) do
    branches = Organisations.list_branches(conn.assigns.current_scope)
    render(conn, :index, branches: branches)
  end

  def new(conn, _params) do
    changeset = Branch.changeset(%Branch{}, %{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"branch" => branch_params}) do
    case Organisations.create_branch(conn.assigns.current_scope, branch_params) do
      {:ok, branch} ->
        AuditLogs.log("branch_created",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "branch",
          target_id: branch.id,
          ip_address: get_ip(conn),
          organisation_id: branch.organisation_id,
          metadata: %{name: branch.name, code: branch.code}
        )

        conn
        |> put_flash(:info, "Branch created.")
        |> redirect(to: ~p"/admin/branches")

      {:error, changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end

  def edit(conn, %{"id" => id}) do
    branch = Organisations.get_branch!(conn.assigns.current_scope, id)
    changeset = Branch.changeset(branch, %{})
    render(conn, :edit, branch: branch, changeset: changeset)
  end

  def update(conn, %{"id" => id, "branch" => branch_params}) do
    branch = Organisations.get_branch!(conn.assigns.current_scope, id)

    case Organisations.update_branch(branch, branch_params) do
      {:ok, branch} ->
        AuditLogs.log("branch_updated",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "branch",
          target_id: branch.id,
          ip_address: get_ip(conn),
          organisation_id: branch.organisation_id,
          metadata: %{name: branch.name}
        )

        conn
        |> put_flash(:info, "Branch updated.")
        |> redirect(to: ~p"/admin/branches")

      {:error, changeset} ->
        render(conn, :edit, branch: branch, changeset: changeset)
    end
  end

  defp get_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end
