defmodule MiwayCreditCore.Customers.DocumentStorage do
  @moduledoc """
  Where KYC document bytes actually live. Local disk today, under
  `priv/kyc_uploads/` — outside `priv/static`, so `Plug.Static` never
  serves it; the only read path is `CustomerController#download_kyc_document`,
  which re-checks scope and permission on every request before calling
  `read_path/3`. Swap this module's internals for S3 (or anything else)
  later without touching the context or controller — every caller only
  knows `store/3`/`read_path/3`/`delete/3`.
  """

  defp root do
    Application.get_env(
      :miway_credit_core,
      :kyc_upload_dir,
      Path.join(:code.priv_dir(:miway_credit_core), "kyc_uploads")
    )
  end

  @doc "Copies the uploaded file to disk under an opaque, server-generated name. Returns {stored_filename, size_bytes}."
  def store(%Plug.Upload{} = upload, organisation_id, customer_id) do
    stored_filename = Ecto.UUID.generate() <> Path.extname(upload.filename)
    dir = customer_dir(organisation_id, customer_id)
    File.mkdir_p!(dir)

    dest = Path.join(dir, stored_filename)
    File.cp!(upload.path, dest)

    {stored_filename, File.stat!(dest).size}
  end

  @doc "The on-disk path for a stored file — built server-side from opaque ids, never from client input, so it can't be used for path traversal."
  def read_path(organisation_id, customer_id, stored_filename) do
    Path.join(customer_dir(organisation_id, customer_id), stored_filename)
  end

  def delete(organisation_id, customer_id, stored_filename) do
    organisation_id
    |> read_path(customer_id, stored_filename)
    |> File.rm()
  end

  defp customer_dir(organisation_id, customer_id) do
    Path.join([root(), organisation_id, customer_id])
  end
end
