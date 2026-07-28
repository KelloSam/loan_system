defmodule MiwayCreditCore.Authorization.ApprovalLimit do
  @moduledoc """
  A monetary ceiling on a permission for a Role. Scoped to
  "applications.approve" for this pass — the clearest, most-requested
  case. Exceeding it is a hard block at approval time, not routed to
  a higher approver (an escalation workflow is Step 9 territory, once
  a real multi-stage application lifecycle exists).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "approval_limits" do
    field :permission_key, :string
    field :max_amount, :decimal

    belongs_to :role, MiwayCreditCore.Authorization.Role, type: :binary_id

    timestamps()
  end

  def changeset(approval_limit, attrs) do
    approval_limit
    |> cast(attrs, [:role_id, :permission_key, :max_amount])
    |> validate_required([:role_id, :permission_key, :max_amount])
    |> validate_inclusion(:permission_key, MiwayCreditCore.Authorization.permission_keys())
    |> validate_number(:max_amount, greater_than: 0)
    |> unique_constraint([:role_id, :permission_key])
    |> foreign_key_constraint(:role_id)
  end
end
