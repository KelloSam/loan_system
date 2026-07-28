defmodule MiwayCreditCore.Authorization do
  @moduledoc """
  Server-side permission enforcement: Role, RolePermission,
  RoleAssignment, ApprovalLimit. Every permission a staff member can
  hold is checked here, not just hidden from a menu — see
  `authorized?/2`.

  The permission catalog is a fixed, code-defined vocabulary (not a
  database table) matching today's real controller actions — no entry
  exists for an action nothing can trigger yet. `applications.submit`/
  `.assess` and `loans.disburse` aren't here: today's LoanApplication
  lifecycle is flat (pending → approved/rejected, no separate submit/
  assess step) and disbursement happens automatically inside approval,
  not as its own action. They get added for real once Step 9
  introduces the state machine they correspond to.
  """

  import Ecto.Query
  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.Authorization.{Role, RolePermission, RoleAssignment, ApprovalLimit}
  alias MiwayCreditCore.Organisations
  alias MiwayCreditCore.Organisations.OrganisationMembership
  alias MiwayCreditCore.Accounts.Scope

  @permission_keys ~w(
    customers.view
    customers.manage
    applications.view
    applications.create
    applications.edit
    applications.approve
    applications.reject
    payments.receive
    payments.reverse
    collateral.manage
    reports.view
    audit.view
  )

  @role_names ~w(platform_administrator organisation_administrator loan_officer)

  @default_permissions %{
    "platform_administrator" => @permission_keys,
    "organisation_administrator" => @permission_keys,
    "loan_officer" => ~w(
      applications.create
      applications.view
      applications.edit
      payments.receive
      customers.manage
      customers.view
      reports.view
    )
  }

  def permission_keys, do: @permission_keys

  @doc """
  Creates an Organisation (via Organisations.create_organisation/1)
  and its 3 default Roles, atomically. Organisations itself stays
  foundational — depends on nothing, including this context — so this
  orchestration lives here, on the dependent side, not there.
  """
  def provision_organisation(attrs) do
    Repo.transaction(fn ->
      with {:ok, organisation} <- Organisations.create_organisation(attrs),
           {:ok, _roles} <- seed_default_roles(Repo, organisation.id) do
        organisation
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Adds a StaffMember to an Organisation (via
  Organisations.add_staff_to_organisation/2) and grants them the Role
  matching their StaffMember.role, atomically — so enrolling someone
  never leaves them with membership but zero permissions.
  """
  def enroll_staff_member(staff_member, organisation_id) do
    Repo.transaction(fn ->
      with {:ok, membership} <- Organisations.add_staff_to_organisation(staff_member.id, organisation_id),
           %Role{} = role <- get_role_by_name(organisation_id, staff_member.role) || {:error, :role_not_seeded},
           {:ok, _assignment} <- assign_role(membership.id, role.id) do
        membership
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Creates the 3 default Roles for an Organisation, each with its
  default permission set. Prefer provision_organisation/1 for a new
  organisation — this is the lower-level piece it (and the Step 6
  backfill migration) builds on.
  """
  def seed_default_roles(repo, organisation_id) do
    Enum.reduce_while(@role_names, {:ok, []}, fn role_name, {:ok, acc} ->
      case create_role_with_permissions(repo, organisation_id, role_name) do
        {:ok, role} -> {:cont, {:ok, [role | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp create_role_with_permissions(repo, organisation_id, role_name) do
    with {:ok, role} <-
           %Role{}
           |> Role.changeset(%{organisation_id: organisation_id, name: role_name})
           |> repo.insert() do
      @default_permissions
      |> Map.fetch!(role_name)
      |> Enum.reduce_while({:ok, role}, fn permission_key, {:ok, role} ->
        %RolePermission{}
        |> RolePermission.changeset(%{role_id: role.id, permission_key: permission_key})
        |> repo.insert()
        |> case do
          {:ok, _} -> {:cont, {:ok, role}}
          {:error, _} = error -> {:halt, error}
        end
      end)
    end
  end

  def get_role_by_name(organisation_id, name) do
    Repo.get_by(Role, organisation_id: organisation_id, name: name)
  end

  @doc "Grants a Role to an OrganisationMembership — the permanent \"home role\" shape (no branch, no expiry)."
  def assign_role(organisation_membership_id, role_id, attrs \\ %{}) do
    %RoleAssignment{}
    |> RoleAssignment.changeset(Map.merge(%{organisation_membership_id: organisation_membership_id, role_id: role_id}, attrs))
    |> Repo.insert()
  end

  @doc "The permission keys a Role grants."
  def permissions_for_role(role_id) do
    RolePermission
    |> where([rp], rp.role_id == ^role_id)
    |> select([rp], rp.permission_key)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Whether the given scope currently holds `permission_key`. Platform
  administrator (`scope.organisation_id == :all`) always passes. A
  customer scope (no staff_member) never does — permissions are a
  staff concept. Otherwise: true if any of the membership's active
  (permanent or unexpired-delegation) RoleAssignments grant it.
  """
  def authorized?(%Scope{organisation_id: :all}, _permission_key), do: true
  def authorized?(%Scope{staff_member: nil}, _permission_key), do: false

  def authorized?(%Scope{staff_member: staff_member, organisation_id: organisation_id}, permission_key) do
    membership = Repo.get_by(OrganisationMembership, staff_member_id: staff_member.id, organisation_id: organisation_id)

    case membership do
      nil -> false
      membership -> permission_key in granted_permission_keys(membership.id)
    end
  end

  defp granted_permission_keys(organisation_membership_id) do
    RoleAssignment
    |> where([ra], ra.organisation_membership_id == ^organisation_membership_id)
    |> Repo.all()
    |> Enum.filter(&RoleAssignment.active?/1)
    |> Enum.flat_map(fn assignment -> permissions_for_role(assignment.role_id) |> MapSet.to_list() end)
    |> MapSet.new()
  end

  @doc """
  Approval limit (if any) this scope's role(s) carry for
  `permission_key`. Returns the lowest applicable limit if more than
  one active role assignment sets one, or nil if unlimited.
  """
  def approval_limit(%Scope{organisation_id: :all}, _permission_key), do: nil
  def approval_limit(%Scope{staff_member: nil}, _permission_key), do: nil

  def approval_limit(%Scope{staff_member: staff_member, organisation_id: organisation_id}, permission_key) do
    membership = Repo.get_by(OrganisationMembership, staff_member_id: staff_member.id, organisation_id: organisation_id)

    case membership do
      nil ->
        nil

      membership ->
        RoleAssignment
        |> where([ra], ra.organisation_membership_id == ^membership.id)
        |> Repo.all()
        |> Enum.filter(&RoleAssignment.active?/1)
        |> Enum.map(& &1.role_id)
        |> Enum.flat_map(fn role_id ->
          ApprovalLimit
          |> where([al], al.role_id == ^role_id and al.permission_key == ^permission_key)
          |> Repo.all()
        end)
        |> Enum.map(& &1.max_amount)
        |> case do
          [] -> nil
          limits -> Enum.min(limits, Decimal)
        end
    end
  end

  def set_approval_limit(role_id, permission_key, max_amount) do
    %ApprovalLimit{}
    |> ApprovalLimit.changeset(%{role_id: role_id, permission_key: permission_key, max_amount: max_amount})
    |> Repo.insert()
  end
end
