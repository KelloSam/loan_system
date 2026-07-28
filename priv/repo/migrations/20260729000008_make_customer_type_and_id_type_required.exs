defmodule MiwayCreditCore.Repo.Migrations.MakeCustomerTypeAndIdTypeRequired do
  use Ecto.Migration

  def change do
    alter table(:customers) do
      modify :customer_type, :string, null: false
      modify :id_type, :string, null: false
      modify :kyc_status, :string, null: false
      remove :address, :string
    end
  end
end
