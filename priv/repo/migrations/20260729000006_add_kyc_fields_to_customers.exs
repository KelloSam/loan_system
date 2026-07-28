defmodule MiwayCreditCore.Repo.Migrations.AddKycFieldsToCustomers do
  @moduledoc """
  Step 7: additive pass. Every new column is nullable here so existing
  rows keep working; the follow-up backfill migration fills them in,
  and the migration after that makes `customer_type`/`id_type` required.
  """

  use Ecto.Migration

  def change do
    alter table(:customers) do
      add :customer_type, :string
      add :id_type, :string

      add :address_line, :string
      add :city, :string
      add :province, :string
      add :postal_code, :string

      add :employment_status, :string
      add :employer_name, :string
      add :occupation, :string
      add :monthly_income, :decimal

      add :business_type, :string
      add :annual_turnover, :decimal
      add :years_in_operation, :integer

      add :kyc_status, :string
      add :kyc_verified_at, :utc_datetime
      add :kyc_verified_by_id, references(:users)
    end
  end
end
