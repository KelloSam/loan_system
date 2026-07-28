defmodule MiwayCreditCore.Repo.Migrations.AddApprovalWorkflowFieldsToProducts do
  @moduledoc """
  Step 11: second-level approval, committee decisions, and separation
  of duties all opt-in per product, same as every other requirement
  flag since Step 8 — a product that leaves these off behaves exactly
  as it did before this migration. requires_separation_of_duties
  defaults true because today's maker-checker is unconditional; this
  preserves that behavior for every existing product.
  """

  use Ecto.Migration

  def change do
    alter table(:products) do
      add :requires_second_level_approval, :boolean, null: false, default: false
      add :second_level_minimum_role, :string

      add :requires_committee_decision, :boolean, null: false, default: false
      add :committee_size, :integer, null: false, default: 3
      add :committee_quorum, :integer, null: false, default: 2

      add :requires_separation_of_duties, :boolean, null: false, default: true
    end
  end
end
