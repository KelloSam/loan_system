defmodule MiwayCreditCore.Customers do
  import Ecto.Query
  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.Customers.{Customer, NextOfKin, Guarantor, KycDocument, Consent, DocumentStorage, MalwareScanner}
  alias MiwayCreditCore.Accounts.Scope

  @doc """
  Returns a paginated list of customers ordered by name, scoped to the
  caller's organisation. Accepts `page:` and `per_page:` opts (defaults: 1, 50).
  """
  def list_customers(%Scope{} = scope, opts \\ []) do
    page     = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 50)
    offset   = (page - 1) * per_page

    Customer
    |> scope_organisation(scope)
    |> order_by([c], asc: c.name)
    |> limit(^per_page)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc "Fetches a customer by id, scoped — a customer belonging to a different organisation raises the same NoResultsError as an unknown id."
  def get_customer!(%Scope{} = scope, id) do
    Customer
    |> scope_organisation(scope)
    |> Repo.get!(id)
  end

  @doc "Creates a customer under the caller's organisation. organisation_id always comes from scope, never from attrs, so it can't be spoofed via form tampering."
  def create_customer(%Scope{organisation_id: organisation_id}, _attrs) when organisation_id == :all do
    raise ArgumentError, "create_customer/2 requires a concrete organisation scope, not :all"
  end

  def create_customer(%Scope{organisation_id: organisation_id}, attrs) do
    # attrs may be atom-keyed (internal/seed callers) or string-keyed
    # (form params) — normalize before merging so cast/3 never sees a
    # map with mixed key types.
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    %Customer{}
    |> Customer.changeset(Map.put(attrs, "organisation_id", organisation_id))
    |> Repo.insert()
  end

  def update_customer(%Customer{} = customer, attrs) do
    customer
    |> Customer.changeset(attrs)
    |> Repo.update()
  end

  def delete_customer(%Customer{} = customer) do
    Repo.delete(customer)
  end

  @doc "Unscoped — used only by seed scripts, which run outside any request/scope context. Never call this from a controller."
  def get_customer_by_email(email) do
    Repo.get_by(Customer, email: email)
  end

  def get_customer_by_phone(phone) do
    Repo.get_by(Customer, phone: phone)
  end

  def get_customer_by_id_number(id_number) do
    Repo.get_by(Customer, id_number: id_number)
  end

  def count_customers(%Scope{} = scope) do
    Customer
    |> scope_organisation(scope)
    |> Repo.aggregate(:count)
  end

  @doc """
  Masks all but the last few characters of an identity number for
  display in list views — e.g. `index.html.heex` shows this, while
  `show.html.heex`/`edit.html.heex` (already gated behind
  `customers.manage`) show the real `id_number`.
  """
  def mask_id_number(nil), do: nil

  def mask_id_number(id_number) when byte_size(id_number) <= 4 do
    String.duplicate("*", byte_size(id_number))
  end

  def mask_id_number(id_number) do
    visible = String.slice(id_number, -4, 4)
    String.duplicate("*", byte_size(id_number) - 4) <> visible
  end

  @doc """
  Exact-match check for an existing customer in the *same organisation*
  sharing an id_number or phone with `attrs` — a soft pre-submission
  warning on top of the hard org-scoped unique constraint, not a
  replacement for it. No fuzzy matching: exact match only.
  """
  def find_potential_duplicates(%Scope{organisation_id: organisation_id}, attrs)
      when organisation_id != :all do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    id_number = attrs["id_number"]
    phone = attrs["phone"]

    # Ecto forbids comparing a field to a pinned value that's nil at
    # runtime (raises, doesn't just no-op) — so each clause is only
    # added when its value is actually present, via dynamic/2, rather
    # than guarding nils inside the query itself.
    conditions =
      [
        id_number && dynamic([c], c.id_number == ^id_number),
        phone && dynamic([c], c.phone == ^phone)
      ]
      |> Enum.reject(&is_nil/1)

    case conditions do
      [] ->
        []

      _ ->
        combined = Enum.reduce(conditions, fn condition, acc -> dynamic(^acc or ^condition) end)

        Customer
        |> where([c], c.organisation_id == ^organisation_id)
        |> where(^combined)
        |> Repo.all()
    end
  end

  # ---------------------------------------------------------------------------
  # KYC verification status — changed only through these, never through
  # update_customer/2, so every transition is deliberate and auditable.
  # ---------------------------------------------------------------------------

  def submit_for_kyc_review(%Customer{} = customer, %Scope{}) do
    customer
    |> Customer.kyc_status_changeset(%{"kyc_status" => "pending_review"})
    |> Repo.update()
  end

  def mark_kyc_verified(%Customer{} = customer, %Scope{user: user}) do
    customer
    |> Customer.kyc_status_changeset(%{
      "kyc_status" => "verified",
      "kyc_verified_at" => DateTime.utc_now() |> DateTime.truncate(:second),
      "kyc_verified_by_id" => user.id,
      "kyc_rejection_reason" => nil
    })
    |> Repo.update()
  end

  def mark_kyc_rejected(%Customer{} = customer, %Scope{user: user}, reason) do
    customer
    |> Customer.kyc_status_changeset(%{
      "kyc_status" => "rejected",
      "kyc_verified_at" => DateTime.utc_now() |> DateTime.truncate(:second),
      "kyc_verified_by_id" => user.id,
      "kyc_rejection_reason" => reason
    })
    |> Repo.update()
  end

  # ---------------------------------------------------------------------------
  # Next of kin — hard-deletable contact info, no evidentiary weight
  # ---------------------------------------------------------------------------

  def list_next_of_kins_for_customer(%Scope{} = scope, customer_id) do
    NextOfKin
    |> scope_organisation(scope)
    |> where([n], n.customer_id == ^customer_id)
    |> order_by([n], asc: n.inserted_at)
    |> Repo.all()
  end

  def get_next_of_kin!(%Scope{} = scope, id) do
    NextOfKin
    |> scope_organisation(scope)
    |> Repo.get!(id)
  end

  @doc "organisation_id derives from the Customer, never from attrs."
  def create_next_of_kin(%Customer{} = customer, attrs) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.put("customer_id", customer.id)
      |> Map.put("organisation_id", customer.organisation_id)

    %NextOfKin{}
    |> NextOfKin.changeset(attrs)
    |> Repo.insert()
  end

  def delete_next_of_kin(%NextOfKin{} = next_of_kin), do: Repo.delete(next_of_kin)

  # ---------------------------------------------------------------------------
  # Guarantors — customer-level records, reusable across future applications
  # ---------------------------------------------------------------------------

  def list_guarantors_for_customer(%Scope{} = scope, customer_id) do
    Guarantor
    |> scope_organisation(scope)
    |> where([g], g.customer_id == ^customer_id)
    |> order_by([g], asc: g.inserted_at)
    |> Repo.all()
  end

  def get_guarantor!(%Scope{} = scope, id) do
    Guarantor
    |> scope_organisation(scope)
    |> Repo.get!(id)
  end

  @doc "organisation_id derives from the Customer, never from attrs."
  def create_guarantor(%Customer{} = customer, attrs) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.put("customer_id", customer.id)
      |> Map.put("organisation_id", customer.organisation_id)

    %Guarantor{}
    |> Guarantor.changeset(attrs)
    |> Repo.insert()
  end

  def delete_guarantor(%Guarantor{} = guarantor), do: Repo.delete(guarantor)

  # ---------------------------------------------------------------------------
  # KYC documents — file bytes on disk via DocumentStorage, metadata here.
  # Never hard-deleted: remove_kyc_document/1 marks status "removed".
  # ---------------------------------------------------------------------------

  def list_kyc_documents_for_customer(%Scope{} = scope, customer_id) do
    KycDocument
    |> scope_organisation(scope)
    |> where([d], d.customer_id == ^customer_id)
    |> order_by([d], desc: d.inserted_at)
    |> Repo.all()
  end

  def get_kyc_document!(%Scope{} = scope, id) do
    KycDocument
    |> scope_organisation(scope)
    |> Repo.get!(id)
  end

  @doc """
  organisation_id derives from the Customer, never from attrs. Scans
  the upload (still plaintext, before DocumentStorage encrypts it —
  a scanner can't meaningfully inspect ciphertext) before ever storing
  it; a blocked upload never touches disk, so there's nothing to clean
  up. Otherwise stores the file first, then its metadata.
  """
  def create_kyc_document(%Customer{} = customer, %Plug.Upload{} = upload, document_type, uploaded_by_id) do
    case MalwareScanner.scan(upload.path) do
      :clean -> do_create_kyc_document(customer, upload, document_type, uploaded_by_id)
      {:infected, reason} -> {:error, {:blocked, reason}}
      {:error, reason} -> {:error, {:blocked, reason}}
    end
  end

  defp do_create_kyc_document(%Customer{} = customer, %Plug.Upload{} = upload, document_type, uploaded_by_id) do
    {stored_filename, size_bytes} = DocumentStorage.store(upload, customer.organisation_id, customer.id)

    attrs = %{
      "organisation_id" => customer.organisation_id,
      "customer_id" => customer.id,
      "document_type" => document_type,
      "stored_filename" => stored_filename,
      "original_filename" => upload.filename,
      "content_type" => upload.content_type,
      "size_bytes" => size_bytes,
      "uploaded_by_id" => uploaded_by_id,
      "uploaded_at" => DateTime.utc_now() |> DateTime.truncate(:second)
    }

    case %KycDocument{} |> KycDocument.changeset(attrs) |> Repo.insert() do
      {:ok, document} ->
        {:ok, document}

      {:error, changeset} ->
        DocumentStorage.delete(customer.organisation_id, customer.id, stored_filename)
        {:error, changeset}
    end
  end

  @doc "The on-disk path — for existence/cleanup checks only, never for reading content directly (bytes are encrypted at rest). Callers must check scope/permission before calling this."
  def kyc_document_path(%KycDocument{} = document) do
    DocumentStorage.read_path(document.organisation_id, document.customer_id, document.stored_filename)
  end

  @doc "The decrypted file bytes to stream for download — callers must check scope/permission before calling this."
  def kyc_document_bytes(%KycDocument{} = document) do
    DocumentStorage.read(document.organisation_id, document.customer_id, document.stored_filename)
  end

  def remove_kyc_document(%KycDocument{} = document) do
    document
    |> KycDocument.void_changeset()
    |> Repo.update()
  end

  @doc """
  Deletes the on-disk bytes (not the row — see `KycDocument`'s
  moduledoc) for every "removed" document whose retention window has
  elapsed. System-wide, no scope — the same shape as
  `Lending.mark_overdue_installments/0`, a background job that isn't
  triggered by any one organisation's request. Returns the list of
  now-purged documents, so the caller (`KycRetentionScheduler`) can
  audit-log each one — matching this codebase's own convention that
  `AuditLogs.log/2` is only ever called from the web/scheduler layer,
  never from inside a context.
  """
  def purge_expired_kyc_documents do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-retention_days() * 24 * 60 * 60, :second)
      |> DateTime.truncate(:second)

    KycDocument
    |> where([d], d.status == "removed" and d.removed_at < ^cutoff)
    |> Repo.all()
    |> Enum.map(fn document ->
      DocumentStorage.delete(document.organisation_id, document.customer_id, document.stored_filename)
      {:ok, purged} = document |> KycDocument.purge_changeset() |> Repo.update()
      purged
    end)
  end

  defp retention_days do
    Application.get_env(:miway_credit_core, :kyc_retention_days, 2555)
  end

  # ---------------------------------------------------------------------------
  # Consent — never hard-deleted: revoke_consent/1 sets revoked_at.
  # ---------------------------------------------------------------------------

  def list_consents_for_customer(%Scope{} = scope, customer_id) do
    Consent
    |> scope_organisation(scope)
    |> where([c], c.customer_id == ^customer_id)
    |> order_by([c], desc: c.inserted_at)
    |> Repo.all()
  end

  def get_consent!(%Scope{} = scope, id) do
    Consent
    |> scope_organisation(scope)
    |> Repo.get!(id)
  end

  @doc "organisation_id derives from the Customer, never from attrs."
  def create_consent(%Customer{} = customer, attrs, recorded_by_id) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.put("customer_id", customer.id)
      |> Map.put("organisation_id", customer.organisation_id)
      |> Map.put("recorded_by_id", recorded_by_id)
      |> Map.put_new("granted_at", DateTime.utc_now() |> DateTime.truncate(:second))

    %Consent{}
    |> Consent.changeset(attrs)
    |> Repo.insert()
  end

  def revoke_consent(%Consent{} = consent) do
    consent
    |> Consent.revoke_changeset()
    |> Repo.update()
  end

  @doc "Whether the customer currently has an active (granted, not revoked) consent of this type."
  def has_active_consent?(%Scope{} = scope, customer_id, consent_type) do
    Consent
    |> scope_organisation(scope)
    |> where([c], c.customer_id == ^customer_id and c.consent_type == ^consent_type and is_nil(c.revoked_at))
    |> Repo.exists?()
  end

  defp stringify_keys(attrs), do: Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

  defp scope_organisation(query, %Scope{organisation_id: :all}), do: query
  defp scope_organisation(query, %Scope{organisation_id: organisation_id}) do
    where(query, organisation_id: ^organisation_id)
  end
end
