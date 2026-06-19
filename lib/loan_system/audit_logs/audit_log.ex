defmodule LoanSystem.AuditLogs.AuditLog do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "audit_logs" do
    field :event, :string
    field :actor_id, :binary_id
    field :actor_email, :string
    field :target_type, :string
    field :target_id, :string
    field :metadata, :map, default: %{}
    field :ip_address, :string

    timestamps(updated_at: false)
  end

  def changeset(log, attrs) do
    log
    |> cast(attrs, [:event, :actor_id, :actor_email, :target_type, :target_id, :metadata, :ip_address])
    |> validate_required([:event])
  end
end
