defmodule MiwayCreditCore.Customers.Consent do
  @moduledoc """
  A record that a customer agreed (or later withdrew agreement) to a
  specific use of their data. Never hard-deleted — `revoked_at` marks
  withdrawal, matching KycDocument's "voided, not deleted" principle,
  so the history of what was ever granted stays intact.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @consent_types ~w(data_processing credit_check marketing_communications other)
  @methods ~w(digital verbal signed_form)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "consents" do
    field :consent_type, :string
    field :method, :string
    field :granted_at, :utc_datetime
    field :revoked_at, :utc_datetime

    belongs_to :organisation, MiwayCreditCore.Organisations.Organisation, type: :binary_id
    belongs_to :customer, MiwayCreditCore.Customers.Customer, type: :binary_id
    belongs_to :recorded_by, MiwayCreditCore.Accounts.User

    timestamps()
  end

  def changeset(consent, attrs) do
    consent
    |> cast(attrs, [
      :organisation_id,
      :customer_id,
      :consent_type,
      :method,
      :granted_at,
      :recorded_by_id
    ])
    |> validate_required([
      :organisation_id,
      :customer_id,
      :consent_type,
      :method,
      :granted_at,
      :recorded_by_id
    ])
    |> validate_inclusion(:consent_type, @consent_types)
    |> validate_inclusion(:method, @methods)
    |> foreign_key_constraint(:organisation_id)
    |> foreign_key_constraint(:customer_id)
    |> foreign_key_constraint(:recorded_by_id)
  end

  def revoke_changeset(consent) do
    change(consent, revoked_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
