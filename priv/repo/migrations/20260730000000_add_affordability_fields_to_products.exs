defmodule MiwayCreditCore.Repo.Migrations.AddAffordabilityFieldsToProducts do
  @moduledoc """
  Step 10 affordability checking is opt-in per product, same as
  requires_guarantor/requires_crb_check — a product that leaves
  requires_affordability_check off behaves exactly as it did before
  this migration. max_debt_to_income_percent always has a value (not
  nullable) even when the flag is off, so the check function never
  needs a nil-handling branch.
  """

  use Ecto.Migration

  def change do
    alter table(:products) do
      add :requires_affordability_check, :boolean, null: false, default: false
      add :max_debt_to_income_percent, :decimal, precision: 5, scale: 2, null: false, default: "40.00"
    end
  end
end
