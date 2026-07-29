defmodule MiwayCreditCore.Customers.KycDocument do
  @moduledoc """
  Metadata for a file uploaded as identity/address/income evidence.
  The actual bytes live on disk via `MiwayCreditCore.Customers.DocumentStorage`
  — `stored_filename` is server-generated and opaque; `original_filename`
  is for display only and must never be used to build a filesystem path.

  Never hard-deleted — a mis-uploaded or superseded document is marked
  `status: "removed"` instead, the same "voided, not deleted" principle
  `PaymentTransaction` uses, so the audit trail always has something to
  point at. Once removed, a retention window applies — see
  `MiwayCreditCore.Customers.purge_expired_kyc_documents/0` — after
  which the bytes are deleted from disk (`status: "purged"`) but this
  row is kept as a tombstone, never the row itself.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @document_types ~w(nrc_copy passport_copy proof_of_address payslip business_registration_certificate other)
  @statuses ~w(active removed purged)
  @allowed_content_types ~w(application/pdf image/jpeg image/png)
  @max_size_bytes 10_000_000

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "kyc_documents" do
    field :document_type, :string
    field :stored_filename, :string
    field :original_filename, :string
    field :content_type, :string
    field :size_bytes, :integer
    field :status, :string, default: "active"
    field :uploaded_at, :utc_datetime
    field :removed_at, :utc_datetime

    belongs_to :organisation, MiwayCreditCore.Organisations.Organisation, type: :binary_id
    belongs_to :customer, MiwayCreditCore.Customers.Customer, type: :binary_id
    belongs_to :uploaded_by, MiwayCreditCore.Accounts.User

    timestamps()
  end

  def changeset(kyc_document, attrs) do
    kyc_document
    |> cast(attrs, [
      :organisation_id, :customer_id, :document_type, :stored_filename,
      :original_filename, :content_type, :size_bytes, :status,
      :uploaded_by_id, :uploaded_at
    ])
    |> validate_required([
      :organisation_id, :customer_id, :document_type, :stored_filename,
      :original_filename, :content_type, :size_bytes, :status,
      :uploaded_by_id, :uploaded_at
    ])
    |> validate_inclusion(:document_type, @document_types)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:content_type, @allowed_content_types,
      message: "must be a PDF, JPEG, or PNG file"
    )
    |> validate_number(:size_bytes, greater_than: 0, less_than_or_equal_to: @max_size_bytes)
    |> foreign_key_constraint(:organisation_id)
    |> foreign_key_constraint(:customer_id)
    |> foreign_key_constraint(:uploaded_by_id)
  end

  def void_changeset(kyc_document) do
    change(kyc_document, status: "removed", removed_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc "The retention window has elapsed — the bytes are gone from disk, but this row (and stored_filename, as a historical pointer) stays, matching this schema's own tombstone philosophy."
  def purge_changeset(kyc_document) do
    change(kyc_document, status: "purged")
  end
end
