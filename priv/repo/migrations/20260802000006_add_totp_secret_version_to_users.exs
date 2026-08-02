defmodule MiwayCreditCore.Repo.Migrations.AddTotpSecretVersionToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :totp_secret_version, :integer, default: 0, null: false
    end
  end
end
