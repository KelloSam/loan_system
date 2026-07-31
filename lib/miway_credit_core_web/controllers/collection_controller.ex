defmodule MiwayCreditCoreWeb.CollectionController do
  use MiwayCreditCoreWeb, :controller

  alias MiwayCreditCore.{Applications, Collections, AuditLogs}
  alias MiwayCreditCoreWeb.Plugs.RequirePermissionPlug

  plug RequirePermissionPlug,
       "collections.manage"
       when action in [
              :create_activity,
              :create_promise,
              :escalate_case,
              :close_case,
              :set_recovery_status
            ]

  plug RequirePermissionPlug, "write_offs.request" when action == :create_write_off_request

  plug RequirePermissionPlug,
       "write_offs.approve" when action in [:approve_write_off, :reject_write_off]

  plug RequirePermissionPlug, "restructuring.request" when action == :create_restructuring_request

  plug RequirePermissionPlug,
       "restructuring.approve" when action in [:approve_restructuring, :reject_restructuring]

  def create_activity(conn, %{"id" => id, "activity" => activity_params}) do
    scope = conn.assigns.current_scope
    application = Applications.get_application!(scope, id)
    collection_case = Collections.get_open_case_for_account(scope, application.loan_account.id)

    attrs =
      activity_params
      |> Map.put("occurred_at", DateTime.utc_now() |> DateTime.truncate(:second))
      |> Map.put("recorded_by_id", conn.assigns.current_user.id)

    case Collections.log_activity(collection_case, attrs) do
      {:ok, activity} ->
        AuditLogs.log("collection_activity_logged",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "collection_activity",
          target_id: activity.id,
          ip_address: get_ip(conn),
          organisation_id: application.organisation_id,
          metadata: %{activity_type: activity.activity_type, outcome: activity.outcome}
        )

        conn
        |> put_flash(:info, "Activity logged.")
        |> redirect(to: ~p"/admin/loans/#{application}")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Could not log activity — check the form and try again.")
        |> redirect(to: ~p"/admin/loans/#{application}")
    end
  end

  def create_promise(conn, %{"id" => id, "promise" => promise_params}) do
    scope = conn.assigns.current_scope
    application = Applications.get_application!(scope, id)
    collection_case = Collections.get_open_case_for_account(scope, application.loan_account.id)

    attrs = Map.put(promise_params, "recorded_by_id", conn.assigns.current_user.id)

    case Collections.record_promise(collection_case, attrs) do
      {:ok, promise} ->
        AuditLogs.log("promise_to_pay_recorded",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "promise_to_pay",
          target_id: promise.id,
          ip_address: get_ip(conn),
          organisation_id: application.organisation_id,
          metadata: %{
            promised_amount: promise.promised_amount,
            promised_date: promise.promised_date
          }
        )

        conn
        |> put_flash(:info, "Promise to pay recorded.")
        |> redirect(to: ~p"/admin/loans/#{application}")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Could not record the promise — check the amount and date.")
        |> redirect(to: ~p"/admin/loans/#{application}")
    end
  end

  def escalate_case(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    application = Applications.get_application!(scope, id)
    collection_case = Collections.get_open_case_for_account(scope, application.loan_account.id)

    {:ok, _} = Collections.escalate_case(collection_case)

    AuditLogs.log("collection_case_escalated",
      actor_id: conn.assigns.current_user.id,
      actor_email: conn.assigns.current_user.email,
      target_type: "collection_case",
      target_id: collection_case.id,
      ip_address: get_ip(conn),
      organisation_id: application.organisation_id
    )

    conn |> put_flash(:info, "Case escalated.") |> redirect(to: ~p"/admin/loans/#{application}")
  end

  def close_case(conn, %{"id" => id} = params) do
    scope = conn.assigns.current_scope
    application = Applications.get_application!(scope, id)
    collection_case = Collections.get_open_case_for_account(scope, application.loan_account.id)
    reason = Map.get(params, "reason", "Not specified")

    {:ok, _} = Collections.close_case(collection_case, reason)

    AuditLogs.log("collection_case_closed",
      actor_id: conn.assigns.current_user.id,
      actor_email: conn.assigns.current_user.email,
      target_type: "collection_case",
      target_id: collection_case.id,
      ip_address: get_ip(conn),
      organisation_id: application.organisation_id,
      metadata: %{reason: reason}
    )

    conn |> put_flash(:info, "Case closed.") |> redirect(to: ~p"/admin/loans/#{application}")
  end

  def set_recovery_status(conn, %{"id" => id, "recovery_status" => recovery_status}) do
    scope = conn.assigns.current_scope
    application = Applications.get_application!(scope, id)
    collection_case = Collections.get_open_case_for_account(scope, application.loan_account.id)

    case Collections.set_recovery_status(
           collection_case,
           recovery_status,
           conn.assigns.current_user.id
         ) do
      {:ok, _} ->
        AuditLogs.log("collection_recovery_status_set",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "collection_case",
          target_id: collection_case.id,
          ip_address: get_ip(conn),
          organisation_id: application.organisation_id,
          metadata: %{recovery_status: recovery_status}
        )

        conn
        |> put_flash(:info, "Recovery status updated.")
        |> redirect(to: ~p"/admin/loans/#{application}")

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not update recovery status.")
        |> redirect(to: ~p"/admin/loans/#{application}")
    end
  end

  def create_restructuring_request(conn, %{"id" => id, "restructuring_request" => params}) do
    scope = conn.assigns.current_scope
    application = Applications.get_application!(scope, id)
    attrs = Map.put(params, "requested_by_id", conn.assigns.current_user.id)

    case Collections.request_restructuring(application.loan_account, attrs) do
      {:ok, request} ->
        AuditLogs.log("restructuring_requested",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "restructuring_request",
          target_id: request.id,
          ip_address: get_ip(conn),
          organisation_id: application.organisation_id,
          metadata: %{additional_term_months: request.additional_term_months}
        )

        conn
        |> put_flash(:info, "Restructuring requested.")
        |> redirect(to: ~p"/admin/loans/#{application}")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Could not submit the restructuring request.")
        |> redirect(to: ~p"/admin/loans/#{application}")
    end
  end

  def approve_restructuring(conn, %{"id" => id, "request_id" => request_id}) do
    scope = conn.assigns.current_scope
    application = Applications.get_application!(scope, id)
    request = Collections.get_restructuring_request!(scope, request_id)

    case Collections.approve_restructuring(request, conn.assigns.current_user.id) do
      {:ok, approved} ->
        AuditLogs.log("restructuring_approved",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "restructuring_request",
          target_id: approved.id,
          ip_address: get_ip(conn),
          organisation_id: application.organisation_id
        )

        conn
        |> put_flash(:info, "Restructuring approved — a new schedule has been generated.")
        |> redirect(to: ~p"/admin/loans/#{application}")

      {:error, :maker_checker_violation} ->
        conn
        |> put_flash(
          :error,
          "You requested this restructuring — a different authorised staff member must approve it."
        )
        |> redirect(to: ~p"/admin/loans/#{application}")

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not approve the restructuring request.")
        |> redirect(to: ~p"/admin/loans/#{application}")
    end
  end

  def reject_restructuring(conn, %{"id" => id, "request_id" => request_id} = params) do
    scope = conn.assigns.current_scope
    application = Applications.get_application!(scope, id)
    request = Collections.get_restructuring_request!(scope, request_id)
    notes = Map.get(params, "notes", "Not specified")

    {:ok, _} = Collections.reject_restructuring(request, conn.assigns.current_user.id, notes)

    AuditLogs.log("restructuring_rejected",
      actor_id: conn.assigns.current_user.id,
      actor_email: conn.assigns.current_user.email,
      target_type: "restructuring_request",
      target_id: request.id,
      ip_address: get_ip(conn),
      organisation_id: application.organisation_id,
      metadata: %{notes: notes}
    )

    conn
    |> put_flash(:info, "Restructuring request rejected.")
    |> redirect(to: ~p"/admin/loans/#{application}")
  end

  def create_write_off_request(conn, %{"id" => id, "write_off_request" => params}) do
    scope = conn.assigns.current_scope
    application = Applications.get_application!(scope, id)
    attrs = Map.put(params, "requested_by_id", conn.assigns.current_user.id)

    case Collections.request_write_off(application.loan_account, attrs) do
      {:ok, request} ->
        AuditLogs.log("write_off_requested",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "write_off_request",
          target_id: request.id,
          ip_address: get_ip(conn),
          organisation_id: application.organisation_id,
          metadata: %{requested_amount: request.requested_amount}
        )

        conn
        |> put_flash(:info, "Write-off requested.")
        |> redirect(to: ~p"/admin/loans/#{application}")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Could not submit the write-off request.")
        |> redirect(to: ~p"/admin/loans/#{application}")
    end
  end

  def approve_write_off(conn, %{"id" => id, "request_id" => request_id}) do
    scope = conn.assigns.current_scope
    application = Applications.get_application!(scope, id)
    request = Collections.get_write_off_request!(scope, request_id)

    case Collections.approve_write_off(request, conn.assigns.current_user.id) do
      {:ok, approved} ->
        AuditLogs.log("write_off_approved",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "write_off_request",
          target_id: approved.id,
          ip_address: get_ip(conn),
          organisation_id: application.organisation_id
        )

        conn
        |> put_flash(:info, "Write-off approved — the balance has been zeroed.")
        |> redirect(to: ~p"/admin/loans/#{application}")

      {:error, :maker_checker_violation} ->
        conn
        |> put_flash(
          :error,
          "You requested this write-off — a different authorised staff member must approve it."
        )
        |> redirect(to: ~p"/admin/loans/#{application}")

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not approve the write-off request.")
        |> redirect(to: ~p"/admin/loans/#{application}")
    end
  end

  def reject_write_off(conn, %{"id" => id, "request_id" => request_id} = params) do
    scope = conn.assigns.current_scope
    application = Applications.get_application!(scope, id)
    request = Collections.get_write_off_request!(scope, request_id)
    notes = Map.get(params, "notes", "Not specified")

    {:ok, _} = Collections.reject_write_off(request, conn.assigns.current_user.id, notes)

    AuditLogs.log("write_off_rejected",
      actor_id: conn.assigns.current_user.id,
      actor_email: conn.assigns.current_user.email,
      target_type: "write_off_request",
      target_id: request.id,
      ip_address: get_ip(conn),
      organisation_id: application.organisation_id,
      metadata: %{notes: notes}
    )

    conn
    |> put_flash(:info, "Write-off request rejected.")
    |> redirect(to: ~p"/admin/loans/#{application}")
  end

  defp get_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end
