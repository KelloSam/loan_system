defmodule Mix.Tasks.MiwayCreditCore.EncryptExistingKycFiles do
  @moduledoc """
  One-time migration: encrypts every KYC document file already on disk
  in the old plaintext format, in place.

  Run this exactly once, right after deploying the commit that adds
  encryption-at-rest for KYC uploads, before any new upload happens.
  Every file this app has ever stored (active or removed — "removed"
  keeps its file too, per the non-destructive KYC policy) predates
  encryption and is still plaintext until this runs; every file stored
  after this commit is already encrypted by `DocumentStorage.store/3`.
  Running this a second time against an already-encrypted file would
  corrupt it — it is not idempotent and is not meant to be re-run.

      mix miway_credit_core.encrypt_existing_kyc_files
  """

  use Mix.Task
  import Ecto.Query

  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.Customers.{DocumentStorage, KycDocument}

  @shortdoc "One-time: encrypts existing plaintext KYC files in place"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    documents =
      Repo.all(
        from d in KycDocument, select: {d.organisation_id, d.customer_id, d.stored_filename}
      )

    Enum.each(documents, fn {organisation_id, customer_id, stored_filename} ->
      path = DocumentStorage.read_path(organisation_id, customer_id, stored_filename)

      if File.exists?(path) do
        DocumentStorage.encrypt_file_in_place!(path)
        Mix.shell().info("Encrypted #{path}")
      else
        Mix.shell().info("Skipped (file missing on disk): #{path}")
      end
    end)

    Mix.shell().info("Done — #{length(documents)} document(s) processed.")
  end
end
