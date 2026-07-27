defmodule MiwayCreditCore.Repo.Migrations.AddStatusAndSessionInvalidationToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :status, :string, default: "active", null: false
      add :sessions_invalidated_at, :naive_datetime
    end
  end
end
