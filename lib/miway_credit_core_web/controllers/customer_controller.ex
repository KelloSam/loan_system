defmodule MiwayCreditCoreWeb.CustomerController do
  use MiwayCreditCoreWeb, :controller

  alias MiwayCreditCore.{Customers, Applications, AuditLogs, CreditReporting}
  alias MiwayCreditCore.Customers.{Customer, NextOfKin, Guarantor, KycDocument, Consent}
  alias MiwayCreditCore.CreditReporting.CreditReport
  alias MiwayCreditCoreWeb.Plugs.RequirePermissionPlug

  plug RequirePermissionPlug, "customers.view" when action in [:index, :show, :download_kyc_document]

  plug RequirePermissionPlug,
       "customers.manage"
       when action in [
              :new, :create, :edit, :update, :delete,
              :create_next_of_kin, :delete_next_of_kin,
              :create_guarantor, :delete_guarantor,
              :create_kyc_document, :remove_kyc_document,
              :create_consent, :revoke_consent,
              :submit_kyc_review, :verify_kyc, :reject_kyc,
              :create_credit_report
            ]

  def index(conn, _params) do
    customers = Customers.list_customers(conn.assigns.current_scope)
    render(conn, :index, customers: customers)
  end

  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    customer = Customers.get_customer!(scope, id)
    applications = Applications.get_applications_for_customer(scope, customer.id)

    render(conn, :show,
      customer: customer,
      applications: applications,
      next_of_kins: Customers.list_next_of_kins_for_customer(scope, customer.id),
      guarantors: Customers.list_guarantors_for_customer(scope, customer.id),
      kyc_documents: Customers.list_kyc_documents_for_customer(scope, customer.id),
      consents: Customers.list_consents_for_customer(scope, customer.id),
      credit_reports: CreditReporting.list_reports_for_customer(scope, customer.id),
      has_credit_check_consent: Customers.has_active_consent?(scope, customer.id, "credit_check"),
      next_of_kin_changeset: NextOfKin.changeset(%NextOfKin{}, %{}),
      guarantor_changeset: Guarantor.changeset(%Guarantor{}, %{}),
      kyc_document_changeset: KycDocument.changeset(%KycDocument{}, %{}),
      consent_changeset: Consent.changeset(%Consent{}, %{}),
      credit_report_changeset: CreditReport.changeset(%CreditReport{}, %{})
    )
  end

  def new(conn, _params) do
    changeset = Customer.changeset(%Customer{}, %{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"customer" => customer_params}) do
    case Customers.create_customer(conn.assigns.current_scope, customer_params) do
      {:ok, customer} ->
        AuditLogs.log("customer_created",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "customer",
          target_id: customer.id,
          ip_address: get_ip(conn),
          metadata: %{name: customer.name, phone: customer.phone}
        )

        conn
        |> put_flash(:info, "Customer created successfully.")
        |> redirect(to: ~p"/admin/customers/#{customer}")

      {:error, changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end

  def edit(conn, %{"id" => id}) do
    customer = Customers.get_customer!(conn.assigns.current_scope, id)
    changeset = Customer.changeset(customer, %{})
    render(conn, :edit, customer: customer, changeset: changeset)
  end

  def update(conn, %{"id" => id, "customer" => customer_params}) do
    customer = Customers.get_customer!(conn.assigns.current_scope, id)

    case Customers.update_customer(customer, customer_params) do
      {:ok, customer} ->
        AuditLogs.log("customer_updated",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "customer",
          target_id: customer.id,
          ip_address: get_ip(conn),
          metadata: %{name: customer.name}
        )

        conn
        |> put_flash(:info, "Customer updated successfully.")
        |> redirect(to: ~p"/admin/customers/#{customer}")

      {:error, changeset} ->
        render(conn, :edit, customer: customer, changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    customer = Customers.get_customer!(conn.assigns.current_scope, id)

    case Customers.delete_customer(customer) do
      {:ok, _} ->
        AuditLogs.log("customer_deleted",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "customer",
          target_id: customer.id,
          ip_address: get_ip(conn),
          metadata: %{name: customer.name}
        )

        conn
        |> put_flash(:info, "Customer deleted.")
        |> redirect(to: ~p"/admin/customers")

      {:error, _} ->
        conn
        |> put_flash(:error, "Cannot delete this customer — they have existing loans.")
        |> redirect(to: ~p"/admin/customers/#{id}")
    end
  end

  # ---------------------------------------------------------------------------
  # Next of kin
  # ---------------------------------------------------------------------------

  def create_next_of_kin(conn, %{"id" => id, "next_of_kin" => attrs}) do
    customer = Customers.get_customer!(conn.assigns.current_scope, id)

    case Customers.create_next_of_kin(customer, attrs) do
      {:ok, next_of_kin} ->
        AuditLogs.log("next_of_kin_added",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "next_of_kin",
          target_id: next_of_kin.id,
          ip_address: get_ip(conn),
          metadata: %{customer_id: customer.id, name: next_of_kin.name}
        )

        conn
        |> put_flash(:info, "Next of kin added.")
        |> redirect(to: ~p"/admin/customers/#{customer}")

      {:error, changeset} ->
        render_show_with_errors(conn, customer, next_of_kin_changeset: changeset)
    end
  end

  def delete_next_of_kin(conn, %{"id" => id, "next_of_kin_id" => next_of_kin_id}) do
    scope = conn.assigns.current_scope
    customer = Customers.get_customer!(scope, id)
    next_of_kin = Customers.get_next_of_kin!(scope, next_of_kin_id)

    {:ok, _} = Customers.delete_next_of_kin(next_of_kin)

    AuditLogs.log("next_of_kin_removed",
      actor_id: conn.assigns.current_user.id,
      actor_email: conn.assigns.current_user.email,
      target_type: "next_of_kin",
      target_id: next_of_kin.id,
      ip_address: get_ip(conn),
      metadata: %{customer_id: customer.id, name: next_of_kin.name}
    )

    conn
    |> put_flash(:info, "Next of kin removed.")
    |> redirect(to: ~p"/admin/customers/#{customer}")
  end

  # ---------------------------------------------------------------------------
  # Guarantors
  # ---------------------------------------------------------------------------

  def create_guarantor(conn, %{"id" => id, "guarantor" => attrs}) do
    customer = Customers.get_customer!(conn.assigns.current_scope, id)

    case Customers.create_guarantor(customer, attrs) do
      {:ok, guarantor} ->
        AuditLogs.log("guarantor_added",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "guarantor",
          target_id: guarantor.id,
          ip_address: get_ip(conn),
          metadata: %{customer_id: customer.id, name: guarantor.name}
        )

        conn
        |> put_flash(:info, "Guarantor added.")
        |> redirect(to: ~p"/admin/customers/#{customer}")

      {:error, changeset} ->
        render_show_with_errors(conn, customer, guarantor_changeset: changeset)
    end
  end

  def create_credit_report(conn, %{"id" => id, "credit_report" => attrs}) do
    scope = conn.assigns.current_scope
    customer = Customers.get_customer!(scope, id)

    case CreditReporting.ManualAdapter.record_report(scope, customer, attrs, conn.assigns.current_user.id) do
      {:ok, credit_report} ->
        AuditLogs.log("credit_report_recorded",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "credit_report",
          target_id: credit_report.id,
          ip_address: get_ip(conn),
          metadata: %{customer_id: customer.id, outcome: credit_report.outcome}
        )

        conn
        |> put_flash(:info, "Credit report recorded.")
        |> redirect(to: ~p"/admin/customers/#{customer}")

      {:error, :consent_required} ->
        conn
        |> put_flash(:error, "This customer has no active credit-check consent on file — grant consent before recording a CRB report.")
        |> redirect(to: ~p"/admin/customers/#{customer}")

      {:error, changeset} ->
        render_show_with_errors(conn, customer, credit_report_changeset: changeset)
    end
  end

  def delete_guarantor(conn, %{"id" => id, "guarantor_id" => guarantor_id}) do
    scope = conn.assigns.current_scope
    customer = Customers.get_customer!(scope, id)
    guarantor = Customers.get_guarantor!(scope, guarantor_id)

    {:ok, _} = Customers.delete_guarantor(guarantor)

    AuditLogs.log("guarantor_removed",
      actor_id: conn.assigns.current_user.id,
      actor_email: conn.assigns.current_user.email,
      target_type: "guarantor",
      target_id: guarantor.id,
      ip_address: get_ip(conn),
      metadata: %{customer_id: customer.id, name: guarantor.name}
    )

    conn
    |> put_flash(:info, "Guarantor removed.")
    |> redirect(to: ~p"/admin/customers/#{customer}")
  end

  # ---------------------------------------------------------------------------
  # KYC documents — never included in AuditLogs metadata: the file bytes,
  # not just the id_number, are exactly what "not publicly accessible"
  # is protecting.
  # ---------------------------------------------------------------------------

  def create_kyc_document(conn, %{
        "id" => id,
        "kyc_document" => %{"document_type" => document_type, "file" => %Plug.Upload{} = upload}
      }) do
    customer = Customers.get_customer!(conn.assigns.current_scope, id)

    case Customers.create_kyc_document(customer, upload, document_type, conn.assigns.current_user.id) do
      {:ok, document} ->
        AuditLogs.log("kyc_document_uploaded",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "kyc_document",
          target_id: document.id,
          ip_address: get_ip(conn),
          metadata: %{customer_id: customer.id, document_type: document.document_type}
        )

        conn
        |> put_flash(:info, "Document uploaded.")
        |> redirect(to: ~p"/admin/customers/#{customer}")

      {:error, changeset} ->
        render_show_with_errors(conn, customer, kyc_document_changeset: changeset)
    end
  end

  def download_kyc_document(conn, %{"id" => id, "document_id" => document_id}) do
    scope = conn.assigns.current_scope
    Customers.get_customer!(scope, id)
    document = Customers.get_kyc_document!(scope, document_id)

    case document.status do
      "active" ->
        conn
        |> put_resp_content_type(document.content_type)
        |> put_resp_header(
          "content-disposition",
          ~s(attachment; filename="#{sanitize_header_value(document.original_filename)}")
        )
        |> send_file(200, Customers.kyc_document_path(document))

      _removed ->
        conn
        |> put_status(:not_found)
        |> put_view(MiwayCreditCoreWeb.ErrorHTML)
        |> render("404.html")
    end
  end

  def remove_kyc_document(conn, %{"id" => id, "document_id" => document_id}) do
    scope = conn.assigns.current_scope
    customer = Customers.get_customer!(scope, id)
    document = Customers.get_kyc_document!(scope, document_id)

    {:ok, _} = Customers.remove_kyc_document(document)

    AuditLogs.log("kyc_document_removed",
      actor_id: conn.assigns.current_user.id,
      actor_email: conn.assigns.current_user.email,
      target_type: "kyc_document",
      target_id: document.id,
      ip_address: get_ip(conn),
      metadata: %{customer_id: customer.id, document_type: document.document_type}
    )

    conn
    |> put_flash(:info, "Document removed.")
    |> redirect(to: ~p"/admin/customers/#{customer}")
  end

  # ---------------------------------------------------------------------------
  # Consent
  # ---------------------------------------------------------------------------

  def create_consent(conn, %{"id" => id, "consent" => attrs}) do
    customer = Customers.get_customer!(conn.assigns.current_scope, id)

    case Customers.create_consent(customer, attrs, conn.assigns.current_user.id) do
      {:ok, consent} ->
        AuditLogs.log("consent_recorded",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "consent",
          target_id: consent.id,
          ip_address: get_ip(conn),
          metadata: %{customer_id: customer.id, consent_type: consent.consent_type}
        )

        conn
        |> put_flash(:info, "Consent recorded.")
        |> redirect(to: ~p"/admin/customers/#{customer}")

      {:error, changeset} ->
        render_show_with_errors(conn, customer, consent_changeset: changeset)
    end
  end

  def revoke_consent(conn, %{"id" => id, "consent_id" => consent_id}) do
    scope = conn.assigns.current_scope
    customer = Customers.get_customer!(scope, id)
    consent = Customers.get_consent!(scope, consent_id)

    {:ok, _} = Customers.revoke_consent(consent)

    AuditLogs.log("consent_revoked",
      actor_id: conn.assigns.current_user.id,
      actor_email: conn.assigns.current_user.email,
      target_type: "consent",
      target_id: consent.id,
      ip_address: get_ip(conn),
      metadata: %{customer_id: customer.id, consent_type: consent.consent_type}
    )

    conn
    |> put_flash(:info, "Consent revoked.")
    |> redirect(to: ~p"/admin/customers/#{customer}")
  end

  # ---------------------------------------------------------------------------
  # KYC verification status
  # ---------------------------------------------------------------------------

  def submit_kyc_review(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    customer = Customers.get_customer!(scope, id)

    {:ok, customer} = Customers.submit_for_kyc_review(customer, scope)

    AuditLogs.log("kyc_submitted_for_review",
      actor_id: conn.assigns.current_user.id,
      actor_email: conn.assigns.current_user.email,
      target_type: "customer",
      target_id: customer.id,
      ip_address: get_ip(conn)
    )

    conn
    |> put_flash(:info, "Submitted for KYC review.")
    |> redirect(to: ~p"/admin/customers/#{customer}")
  end

  def verify_kyc(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    customer = Customers.get_customer!(scope, id)

    {:ok, customer} = Customers.mark_kyc_verified(customer, scope)

    AuditLogs.log("kyc_verified",
      actor_id: conn.assigns.current_user.id,
      actor_email: conn.assigns.current_user.email,
      target_type: "customer",
      target_id: customer.id,
      ip_address: get_ip(conn)
    )

    conn
    |> put_flash(:info, "KYC verified.")
    |> redirect(to: ~p"/admin/customers/#{customer}")
  end

  def reject_kyc(conn, %{"id" => id} = params) do
    scope = conn.assigns.current_scope
    customer = Customers.get_customer!(scope, id)
    reason = Map.get(params, "reason", "Not specified")

    {:ok, customer} = Customers.mark_kyc_rejected(customer, scope, reason)

    AuditLogs.log("kyc_rejected",
      actor_id: conn.assigns.current_user.id,
      actor_email: conn.assigns.current_user.email,
      target_type: "customer",
      target_id: customer.id,
      ip_address: get_ip(conn),
      metadata: %{reason: reason}
    )

    conn
    |> put_flash(:info, "KYC rejected.")
    |> redirect(to: ~p"/admin/customers/#{customer}")
  end

  # Re-renders the customer show page with every assign it needs,
  # overriding just the one changeset that failed validation — mirrors
  # LoanController's render_show_with_errors/3 for the same reason: a
  # bad submission on any of the inline forms must never crash on a
  # missing assign.
  defp render_show_with_errors(conn, customer, overrides) do
    scope = conn.assigns.current_scope
    customer = Customers.get_customer!(scope, customer.id)
    applications = Applications.get_applications_for_customer(scope, customer.id)

    assigns =
      [
        customer: customer,
        applications: applications,
        next_of_kins: Customers.list_next_of_kins_for_customer(scope, customer.id),
        guarantors: Customers.list_guarantors_for_customer(scope, customer.id),
        kyc_documents: Customers.list_kyc_documents_for_customer(scope, customer.id),
        consents: Customers.list_consents_for_customer(scope, customer.id),
        credit_reports: CreditReporting.list_reports_for_customer(scope, customer.id),
        has_credit_check_consent: Customers.has_active_consent?(scope, customer.id, "credit_check"),
        next_of_kin_changeset: NextOfKin.changeset(%NextOfKin{}, %{}),
        guarantor_changeset: Guarantor.changeset(%Guarantor{}, %{}),
        kyc_document_changeset: KycDocument.changeset(%KycDocument{}, %{}),
        consent_changeset: Consent.changeset(%Consent{}, %{}),
        credit_report_changeset: CreditReport.changeset(%CreditReport{}, %{})
      ]
      |> Keyword.merge(overrides)

    conn
    |> put_status(:ok)
    |> render(:show, assigns)
  end

  defp sanitize_header_value(value), do: String.replace(value, ~r/[\r\n"]/, "")

  defp get_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end
