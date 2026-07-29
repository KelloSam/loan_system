defmodule MiwayCreditCore.Repo.Migrations.AddRemovedAtToKycDocuments do
  @moduledoc """
  Needed to know how long a "removed" document has been removed, for
  the retention/purge scheduler — relying on updated_at would be
  fragile if the row is ever touched for any other reason later.
  """

  use Ecto.Migration

  def change do
    alter table(:kyc_documents) do
      add :removed_at, :utc_datetime
    end

    execute(
      "UPDATE kyc_documents SET removed_at = updated_at WHERE status = 'removed'",
      "UPDATE kyc_documents SET removed_at = NULL WHERE status = 'removed'"
    )
  end
end
