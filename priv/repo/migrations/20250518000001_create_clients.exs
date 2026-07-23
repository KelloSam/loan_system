defmodule MiwayCreditCore.Repo.Migrations.CreateClients do
  use Ecto.Migration

  def change do
    create table(:clients, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :phone, :string, null: false
      add :id_number, :string, null: false
      add :email, :string
      add :address, :string
      add :active, :boolean, default: true, null: false
      add :total_loans, :integer, default: 0, null: false
      add :current_balance, :decimal, precision: 15, scale: 2, default: 0.0

      timestamps()
    end

    create unique_index(:clients, [:id_number])
    create unique_index(:clients, [:phone])
    create index(:clients, [:email])
  end
end

