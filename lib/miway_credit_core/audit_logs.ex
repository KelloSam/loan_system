defmodule MiwayCreditCore.AuditLogs do
  import Ecto.Query
  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.AuditLogs.AuditLog
  alias MiwayCreditCore.Accounts.Scope

  # Every event name this app currently logs, for the audit-log filter
  # dropdown — not enforced anywhere (log/2 accepts any event), just a
  # fixed, code-defined vocabulary so the filter doesn't need updating
  # by hand every time a new event is added at a call site. Mirrors the
  # Authorization module's @permission_keys precedent.
  @event_names ~w(
    2fa_blocked_lockout 2fa_disabled 2fa_enabled 2fa_failure 2fa_success
    collateral_added collateral_removed
    collection_activity_logged collection_case_closed collection_case_escalated
    collection_recovery_status_set
    consent_recorded consent_revoked
    credit_report_recorded
    customer_created customer_deleted customer_updated
    guarantor_added guarantor_removed
    kyc_document_removed kyc_document_uploaded kyc_rejected kyc_submitted_for_review kyc_verified
    loan_account_disbursement_reversed
    loan_application_approved loan_application_assessed loan_application_conditionally_approved
    loan_application_conditions_cleared loan_application_created loan_application_disbursed
    loan_application_referred loan_application_rejected loan_application_withdrawn
    login_blocked_lockout login_failure login_success logout
    next_of_kin_added next_of_kin_removed
    password_reset_completed password_reset_requested
    payment_failed payment_marked_failed payment_recorded payment_voided
    product_activated product_created product_retired product_updated
    promise_to_pay_recorded
    restructuring_approved restructuring_rejected restructuring_requested
    write_off_approved write_off_rejected write_off_requested
  )

  def event_names, do: @event_names

  @doc """
  Writes an audit event. Always returns :ok — a failed write never crashes
  the calling request, so the main business flow is never blocked by logging.

  Options:
    - actor_id:        id of the Accounts.User who performed the action (integer)
    - actor_email:     email of that user (stored so logs remain readable even
                       if the user record is later deleted)
    - target_type:     "loan", "customer", "payment", etc.
    - target_id:       ID of the affected record
    - metadata:        map of extra context (amounts, names, etc.)
    - ip_address:      request IP as a string
    - organisation_id: the org this event pertains to. Pass the affected
                       record's own organisation_id when there is one;
                       nil for genuinely pre-auth events (login, password
                       reset) — audit_logs is a platform-wide security log
                       that only sometimes pertains to a specific org.
  """
  def log(event, opts \\ []) do
    attrs = %{
      event: to_string(event),
      actor_id: opts[:actor_id],
      actor_email: opts[:actor_email],
      target_type: opts[:target_type],
      target_id: opts[:target_id] && to_string(opts[:target_id]),
      metadata: opts[:metadata] || %{},
      ip_address: opts[:ip_address],
      organisation_id: opts[:organisation_id]
    }

    %AuditLog{}
    |> AuditLog.changeset(attrs)
    |> Repo.insert()

    :ok
  end

  @doc "Returns the most recent audit events for the scope's organisation, newest first."
  def list_recent(%Scope{} = scope, limit \\ 100) do
    AuditLog
    |> scope_organisation(scope)
    |> order_by([l], desc: l.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Filtered/searched audit events, newest first, scoped to the caller's
  organisation. `filters` may include:
    - "event":       exact event name
    - "actor_email": partial match
    - "from"/"to":   ISO8601 dates, inclusive, matched against inserted_at
  """
  def list_filtered(%Scope{} = scope, filters, limit \\ 200) do
    AuditLog
    |> scope_organisation(scope)
    |> apply_filters(filters)
    |> order_by([l], desc: l.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Count of audit events recorded today, scoped to the caller's organisation."
  def count_today(%Scope{} = scope) do
    start_of_day = NaiveDateTime.new!(Date.utc_today(), ~T[00:00:00])

    AuditLog
    |> scope_organisation(scope)
    |> where([l], l.inserted_at >= ^start_of_day)
    |> select([l], count(l.id))
    |> Repo.one()
  end

  @doc """
  A CSV export of audit events matching `filters`, scoped to the caller's
  organisation. Hand-built rather than pulling in a CSV dependency, same
  approach as Reports.loans_csv/1.
  """
  def audit_csv(%Scope{} = scope, filters \\ %{}) do
    header = ~w(time event actor target_type target_id ip_address)

    rows =
      scope
      |> list_filtered(filters, 10_000)
      |> Enum.map(fn log ->
        [
          NaiveDateTime.to_iso8601(log.inserted_at),
          log.event,
          log.actor_email || "",
          log.target_type || "",
          log.target_id || "",
          log.ip_address || ""
        ]
      end)

    [header | rows]
    |> Enum.map(&csv_row/1)
    |> Enum.join()
  end

  defp scope_organisation(query, %Scope{organisation_id: :all}), do: query
  defp scope_organisation(query, %Scope{organisation_id: organisation_id}) do
    where(query, organisation_id: ^organisation_id)
  end

  defp apply_filters(query, filters) do
    query
    |> filter_event(filters["event"])
    |> filter_actor_email(filters["actor_email"])
    |> filter_from(filters["from"])
    |> filter_to(filters["to"])
  end

  defp filter_event(query, event) when event in [nil, ""], do: query
  defp filter_event(query, event), do: where(query, [l], l.event == ^event)

  defp filter_actor_email(query, actor_email) when actor_email in [nil, ""], do: query
  defp filter_actor_email(query, actor_email) do
    where(query, [l], ilike(l.actor_email, ^"%#{actor_email}%"))
  end

  defp filter_from(query, date) when date in [nil, ""], do: query
  defp filter_from(query, date) do
    case Date.from_iso8601(date) do
      {:ok, date} -> where(query, [l], l.inserted_at >= ^NaiveDateTime.new!(date, ~T[00:00:00]))
      {:error, _} -> query
    end
  end

  defp filter_to(query, date) when date in [nil, ""], do: query
  defp filter_to(query, date) do
    case Date.from_iso8601(date) do
      {:ok, date} -> where(query, [l], l.inserted_at <= ^NaiveDateTime.new!(date, ~T[23:59:59]))
      {:error, _} -> query
    end
  end

  defp csv_row(fields) do
    fields
    |> Enum.map(&csv_escape/1)
    |> Enum.join(",")
    |> Kernel.<>("\r\n")
  end

  defp csv_escape(field) do
    field = to_string(field)

    if String.contains?(field, [",", "\"", "\n"]) do
      "\"" <> String.replace(field, "\"", "\"\"") <> "\""
    else
      field
    end
  end
end
