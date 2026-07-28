defmodule MiwayCreditCore.Repo.Migrations.AddAllocationOrderToOrganisationSettings do
  @moduledoc """
  Step 13: the order in which a payment pays down what's owed on a
  loan. Defaults to penalty before interest before principal — see
  Payments.record_payment/2 and OrganisationSettings.changeset/2 for
  the allowed component values.
  """

  use Ecto.Migration

  def change do
    alter table(:organisation_settings) do
      add :allocation_order, {:array, :string}, null: false, default: ["penalty", "interest", "principal"]
    end
  end
end
