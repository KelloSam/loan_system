defmodule MiwayCreditCore.Repo.Migrations.CreateCustomerUsers do
  use Ecto.Migration

  def change do
    create table(:customer_users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users), null: false
      add :customer_id, references(:customers, type: :binary_id), null: false

      timestamps()
    end

    create unique_index(:customer_users, [:user_id])
    create index(:customer_users, [:customer_id])
  end
end
