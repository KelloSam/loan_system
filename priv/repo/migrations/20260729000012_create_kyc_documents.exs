defmodule MiwayCreditCore.Repo.Migrations.CreateKycDocuments do
  use Ecto.Migration

  def change do
    create table(:kyc_documents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organisation_id, references(:organisations, type: :binary_id), null: false
      add :customer_id, references(:customers, type: :binary_id), null: false

      add :document_type, :string, null: false
      add :stored_filename, :string, null: false
      add :original_filename, :string, null: false
      add :content_type, :string, null: false
      add :size_bytes, :integer, null: false
      add :status, :string, null: false, default: "active"
      add :uploaded_by_id, references(:users), null: false
      add :uploaded_at, :utc_datetime, null: false

      timestamps()
    end

    create index(:kyc_documents, [:organisation_id, :customer_id])
  end
end
