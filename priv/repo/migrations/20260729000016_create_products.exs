defmodule MiwayCreditCore.Repo.Migrations.CreateProducts do
  use Ecto.Migration

  def change do
    create table(:products, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organisation_id, references(:organisations, type: :binary_id), null: false

      add :name, :string, null: false
      add :description, :string

      add :minimum_principal, :decimal, precision: 15, scale: 2, null: false
      add :maximum_principal, :decimal, precision: 15, scale: 2, null: false
      add :interest_method, :string, null: false
      add :interest_rate, :decimal, precision: 6, scale: 2, null: false
      add :minimum_term_months, :integer, null: false
      add :maximum_term_months, :integer, null: false
      add :repayment_frequency, :string, null: false

      add :origination_fee_percent, :decimal, precision: 6, scale: 2, null: false, default: "0.00"
      add :late_payment_penalty_percent, :decimal, precision: 6, scale: 2, null: false, default: "0.00"
      add :grace_period_days, :integer, null: false, default: 0

      add :requires_collateral, :boolean, null: false, default: false
      add :requires_guarantor, :boolean, null: false, default: false
      add :minimum_guarantors, :integer, null: false, default: 0
      add :requires_crb_check, :boolean, null: false, default: false
      add :minimum_approval_role, :string

      add :status, :string, null: false, default: "active"
      add :effective_from, :date, null: false
      add :effective_until, :date

      add :created_by_id, references(:users)

      timestamps()
    end

    create unique_index(:products, [:organisation_id, :name])
    create index(:products, [:organisation_id, :status])
  end
end
