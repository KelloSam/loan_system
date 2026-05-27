defmodule LoanSystem.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :email, :string, null: false
      add :password_hash, :string, null: false
      add :role, :string, null: false, default: "client"

      timestamps()
    end

    # Create unique index for email
    create unique_index(:users, [:email])
  end
end
