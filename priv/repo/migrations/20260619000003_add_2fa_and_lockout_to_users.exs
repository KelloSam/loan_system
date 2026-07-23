defmodule MiwayCreditCore.Repo.Migrations.Add2faAndLockoutToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :totp_secret, :string
      add :totp_enabled, :boolean, default: false, null: false
      add :failed_attempts, :integer, default: 0, null: false
      add :locked_until, :naive_datetime
    end
  end
end
