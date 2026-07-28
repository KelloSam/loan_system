defmodule MiwayCreditCore.AuditLogs.AuditLog do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "audit_logs" do
    field :event, :string
    field :actor_id, :integer
    field :actor_email, :string
    field :target_type, :string
    field :target_id, :string
    field :metadata, :map, default: %{}
    field :ip_address, :string

    # Nullable, unlike every other organisation-owned table: some
    # events (a failed login for an unknown email, a lockout before
    # any org is resolved) happen with no organisation in context at
    # all — audit_logs is a platform-wide security log that only
    # sometimes pertains to a specific org.
    belongs_to :organisation, MiwayCreditCore.Organisations.Organisation, type: :binary_id

    timestamps(updated_at: false, type: :naive_datetime_usec)
  end

  def changeset(log, attrs) do
    log
    |> cast(attrs, [:event, :actor_id, :actor_email, :target_type, :target_id, :metadata, :ip_address,
                   :organisation_id])
    |> validate_required([:event])
    |> foreign_key_constraint(:organisation_id)
  end
end
