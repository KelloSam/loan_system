defmodule MiwayCreditCore.Authorization do
  @moduledoc """
  Server-side permission enforcement: Role, RolePermission,
  RoleAssignment, ApprovalLimit. Every permission a staff member can
  hold is checked here, not just hidden from a menu — see
  `authorized?/2`.

  The permission catalog is a fixed, code-defined vocabulary (not a
  database table) matching today's real controller actions — no entry
  exists for an action nothing can trigger yet. `applications.create`
  covers submission (no separate `applications.submit` key — they're
  the same action, a rename would be pure churn). `applications.assess`,
  `applications.withdraw`, and `loans.disburse` were added in Step 9,
  once `LoanApplication`'s state machine grew real assess/withdraw/
  disburse steps distinct from the create/approve/reject it had before
  — see `MiwayCreditCore.Applications.assess_application/3`,
  `withdraw_application/2`, `disburse_application/2`.
  """

  import Ecto.Query
  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.Authorization.{Role, RolePermission, RoleAssignment, ApprovalLimit}
  alias MiwayCreditCore.Organisations
  alias MiwayCreditCore.Organisations.OrganisationMembership
  alias MiwayCreditCore.Products
  alias MiwayCreditCore.Accounting.GeneralLedger
  alias MiwayCreditCore.Accounts.Scope

  @permission_keys ~w(
    customers.view
    customers.manage
    applications.view
    applications.create
    applications.edit
    applications.assess
    applications.approve
    applications.reject
    applications.withdraw
    loans.disburse
    payments.receive
    payments.reverse
    collateral.manage
    products.view
    products.manage
    reports.view
    audit.view
    collections.view
    collections.manage
    write_offs.request
    write_offs.approve
    restructuring.request
    restructuring.approve
  )

  @role_names ~w(platform_administrator organisation_administrator loan_officer)

  # Ordered lowest to highest authority — used by role_meets_minimum?/2
  # for a product's `minimum_approval_role`, a different axis from
  # ApprovalLimit's per-role dollar ceiling: "this product always needs
  # at least this role," regardless of amount.
  @role_tiers @role_names |> Enum.reverse()

  @default_permissions %{
    "platform_administrator" => @permission_keys,
    "organisation_administrator" => @permission_keys,
    "loan_officer" => ~w(
      applications.create
      applications.view
      applications.edit
      applications.assess
      applications.withdraw
      payments.receive
      customers.manage
      customers.view
      products.view
      reports.view
      collections.view
      collections.manage
      write_offs.request
      restructuring.request
    )
  }

  def permission_keys, do: @permission_keys

  @doc """
  Creates an Organisation (via Organisations.create_organisation/1),
  its 3 default Roles, and a default "Standard Loan" product,
  atomically. Organisations itself stays foundational — depends on
  nothing, including this context — so this orchestration lives here,
  on the dependent side, not there.
  """
  def provision_organisation(attrs) do
    Repo.transaction(fn ->
      with {:ok, organisation} <- Organisations.create_organisation(attrs),
           {:ok, _roles} <- seed_default_roles(Repo, organisation.id),
           {:ok, _product} <- seed_default_product(organisation.id),
           {:ok, _accounts} <- GeneralLedger.seed_chart_of_accounts(organisation.id) do
        organisation
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  The same "Standard Loan" terms the Step 8 migration backfilled for
  every pre-existing organisation — 18.00% reducing balance, monthly,
  no fee/penalty/grace, no requirements, generous bounds — so a fresh
  organisation can originate loans immediately, exactly as it could
  before configurable products existed.
  """
  def seed_default_product(organisation_id) do
    scope = %Scope{organisation_id: organisation_id}

    Products.create_product(scope, %{
      "name" => "Standard Loan",
      "description" => "Default product — 18% reducing-balance, no requirements.",
      "minimum_principal" => "0.01",
      "maximum_principal" => "999999999.99",
      "interest_method" => "reducing_balance",
      "interest_rate" => "18.00",
      "minimum_term_months" => "1",
      "maximum_term_months" => "360",
      "repayment_frequency" => "monthly",
      "effective_from" => Date.utc_today()
    })
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

  @doc """
  Whether the scope currently holds a role at or above `minimum_role`
  in authority (`loan_officer < organisation_administrator <
  platform_administrator`) — a product's `minimum_approval_role` gate.
  A different axis from `approval_limit/2`'s per-role dollar ceiling:
  "this product always needs at least this role," regardless of
  amount. `nil` minimum_role means no gate at all.
  """
  def role_meets_minimum?(_scope, nil), do: true
  def role_meets_minimum?(%Scope{organisation_id: :all}, _minimum_role), do: true
  def role_meets_minimum?(%Scope{staff_member: nil}, _minimum_role), do: false

  def role_meets_minimum?(%Scope{staff_member: staff_member, organisation_id: organisation_id}, minimum_role) do
    membership = Repo.get_by(OrganisationMembership, staff_member_id: staff_member.id, organisation_id: organisation_id)

    case membership do
      nil ->
        false

      membership ->
        minimum_tier = Enum.find_index(@role_tiers, &(&1 == minimum_role))

        membership.id
        |> held_role_names()
        |> Enum.map(&Enum.find_index(@role_tiers, fn tier -> tier == &1 end))
        |> Enum.any?(fn tier -> tier && minimum_tier && tier >= minimum_tier end)
    end
  end

  defp held_role_names(organisation_membership_id) do
    RoleAssignment
    |> where([ra], ra.organisation_membership_id == ^organisation_membership_id)
    |> Repo.all()
    |> Enum.filter(&RoleAssignment.active?/1)
    |> Enum.map(fn assignment -> Repo.get!(Role, assignment.role_id).name end)
  end

  def set_approval_limit(role_id, permission_key, max_amount) do
    %ApprovalLimit{}
    |> ApprovalLimit.changeset(%{role_id: role_id, permission_key: permission_key, max_amount: max_amount})
    |> Repo.insert()
  end
end
