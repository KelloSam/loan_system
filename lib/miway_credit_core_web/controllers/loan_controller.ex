defmodule MiwayCreditCoreWeb.LoanController do
  use MiwayCreditCoreWeb, :controller

  alias MiwayCreditCore.{Applications, Lending, Payments, Customers, Products, AuditLogs, Organisations, Repo}
  alias MiwayCreditCore.Applications.{LoanApplication, Collateral}
  alias MiwayCreditCore.Payments.PaymentTransaction
  alias MiwayCreditCoreWeb.Plugs.RequirePermissionPlug

  plug RequirePermissionPlug, "applications.view" when action in [:index, :show, :receipt]
  plug RequirePermissionPlug, "applications.create" when action in [:new, :create]
  plug RequirePermissionPlug, "applications.edit" when action in [:edit, :update, :delete]
  plug RequirePermissionPlug, "applications.assess" when action == :assess
  plug RequirePermissionPlug, "applications.approve" when action in [:approve, :conditionally_approve, :clear_conditions]
  plug RequirePermissionPlug, "applications.reject" when action in [:reject, :refer]
  plug RequirePermissionPlug, "loans.disburse" when action in [:disburse, :reverse_disbursement]
  plug RequirePermissionPlug, "applications.withdraw" when action == :withdraw
  plug RequirePermissionPlug, "payments.receive" when action in [:create_payment, :record_failed_payment]
  plug RequirePermissionPlug, "payments.reverse" when action in [:void_payment, :fail_payment]
  plug RequirePermissionPlug, "collateral.manage" when action in [:create_collateral, :delete_collateral]

  def index(conn, _params) do
    applications = Applications.list_applications(conn.assigns.current_scope)
    render(conn, :index, applications: applications)
  end

  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    application = Applications.get_application!(scope, id)
    fraud_signals = Applications.fraud_signals(application)
    payment_changeset = PaymentTransaction.changeset(%PaymentTransaction{}, %{})
    failed_payment_changeset = PaymentTransaction.failed_attempt_changeset(%PaymentTransaction{}, %{})
    collateral_changeset = Collateral.changeset(%Collateral{}, %{})

    {account, interest, installments, transactions, collaterals, days_past_due} =
      case application.loan_account do
        nil ->
          {nil, nil, [], [], [], 0}

        account ->
          {
            account,
            Lending.compound_interest_details(account),
            Lending.list_installments_for_account(scope, account.id),
            Payments.list_transactions_for_account(scope, account.id),
            Applications.list_collaterals_for_account(scope, account.id),
            Lending.days_past_due(account)
          }
      end

    render(conn, :show,
      application: application,
      account: account,
      interest: interest,
      installments: installments,
      transactions: transactions,
      payment_changeset: payment_changeset,
      failed_payment_changeset: failed_payment_changeset,
      collateral_changeset: collateral_changeset,
      collaterals: collaterals,
      fraud_signals: fraud_signals,
      days_past_due: days_past_due
    )
  end

  def new(conn, _params) do
    customers = Customers.list_customers(conn.assigns.current_scope)
    products = Products.list_available_products(conn.assigns.current_scope)
    changeset = LoanApplication.changeset(%LoanApplication{}, %{})
    render(conn, :new, changeset: changeset, customers: customers, products: products)
  end

  def create(conn, %{"loan_application" => application_params}) do
    case Applications.create_application(conn.assigns.current_scope, application_params) do
      {:ok, application} ->
        AuditLogs.log("loan_application_created",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "loan_application",
          target_id: application.id,
          ip_address: get_ip(conn),
          metadata: %{requested_amount: application.requested_amount, customer_id: application.customer_id}
        )

        conn
        |> put_flash(:info, "Loan application created successfully.")
        |> redirect(to: ~p"/admin/loans/#{application}")

      {:error, :pending_application_exists} ->
        conn
        |> put_flash(:error, "Blocked: this customer already has a pending application. Resolve the existing application before creating a new one.")
        |> redirect(to: ~p"/admin/loans/new")

      {:error, :rejection_cooldown} ->
        conn
        |> put_flash(:error, "Blocked: this customer was rejected within the last 30 days. New applications are frozen during the cooling-off period.")
        |> redirect(to: ~p"/admin/loans/new")

      {:error, :product_required} ->
        conn
        |> put_flash(:error, "Select a loan product.")
        |> redirect(to: ~p"/admin/loans/new")

      {:error, :product_unavailable} ->
        conn
        |> put_flash(:error, "That product is no longer available. Choose a different one.")
        |> redirect(to: ~p"/admin/loans/new")

      {:error, :amount_below_minimum} ->
        conn
        |> put_flash(:error, "Requested amount is below this product's minimum principal.")
        |> redirect(to: ~p"/admin/loans/new")

      {:error, :amount_above_maximum} ->
        conn
        |> put_flash(:error, "Requested amount is above this product's maximum principal.")
        |> redirect(to: ~p"/admin/loans/new")

      {:error, :term_below_minimum} ->
        conn
        |> put_flash(:error, "Requested term is shorter than this product's minimum term.")
        |> redirect(to: ~p"/admin/loans/new")

      {:error, :term_above_maximum} ->
        conn
        |> put_flash(:error, "Requested term is longer than this product's maximum term.")
        |> redirect(to: ~p"/admin/loans/new")

      {:error, changeset} ->
        customers = Customers.list_customers(conn.assigns.current_scope)
        products = Products.list_available_products(conn.assigns.current_scope)
        render(conn, :new, changeset: changeset, customers: customers, products: products)
    end
  end

  def edit(conn, %{"id" => id}) do
    application = Applications.get_application!(conn.assigns.current_scope, id)
    changeset = LoanApplication.changeset(application, %{})
    render(conn, :edit, application: application, changeset: changeset)
  end

  def update(conn, %{"id" => id, "loan_application" => application_params}) do
    application = Applications.get_application!(conn.assigns.current_scope, id)

    case Applications.update_application(application, application_params) do
      {:ok, application} ->
        conn
        |> put_flash(:info, "Application updated successfully.")
        |> redirect(to: ~p"/admin/loans/#{application}")

      {:error, changeset} ->
        render(conn, :edit, application: application, changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    application = Applications.get_application!(conn.assigns.current_scope, id)

    case Applications.delete_application(application) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Application deleted.")
        |> redirect(to: ~p"/admin/loans")

      {:error, _} ->
        conn
        |> put_flash(:error, "Cannot delete this application.")
        |> redirect(to: ~p"/admin/loans/#{id}")
    end
  end

  def assess(conn, %{"id" => id} = params) do
    application = Applications.get_application!(conn.assigns.current_scope, id)
    notes = Map.get(params, "notes")

    case Applications.assess_application(application, conn.assigns.current_scope, notes) do
      {:ok, application} ->
        AuditLogs.log("loan_application_assessed",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "loan_application",
          target_id: application.id,
          ip_address: get_ip(conn),
          metadata: %{customer_id: application.customer_id}
        )

        conn
        |> put_flash(:info, "Application assessed — ready for a decision.")
        |> redirect(to: ~p"/admin/loans/#{application}")

      {:error, :invalid_status} ->
        conn
        |> put_flash(:error, "This application isn't pending — it can't be assessed.")
        |> redirect(to: ~p"/admin/loans/#{id}")

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not assess application.")
        |> redirect(to: ~p"/admin/loans/#{id}")
    end
  end

  def approve(conn, %{"id" => id} = params) do
    application = Applications.get_application!(conn.assigns.current_scope, id)
    attestation = attests_no_conflict_of_interest?(params)

    case Applications.approve_application(application, conn.assigns.current_scope, attestation) do
      {:ok, application} ->
        AuditLogs.log("loan_application_approved",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "loan_application",
          target_id: application.id,
          ip_address: get_ip(conn),
          metadata: %{requested_amount: application.requested_amount, customer_id: application.customer_id, level_status: application.status}
        )

        message =
          if application.status == "approved",
            do: "Application approved — ready to disburse.",
            else: "Level approved — awaiting the next required approval."

        conn
        |> put_flash(:info, message)
        |> redirect(to: ~p"/admin/loans/#{application}")

      {:error, reason} ->
        conn
        |> put_flash(:error, approval_error_message(reason))
        |> redirect(to: ~p"/admin/loans/#{id}")
    end
  end

  def reject(conn, %{"id" => id} = params) do
    application = Applications.get_application!(conn.assigns.current_scope, id)
    reason = Map.get(params, "reason", "Not specified")
    decline_reason_category = Map.get(params, "decline_reason_category", "other")

    case Applications.reject_application(application, conn.assigns.current_scope, reason, decline_reason_category) do
      {:ok, application} ->
        AuditLogs.log("loan_application_rejected",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "loan_application",
          target_id: application.id,
          ip_address: get_ip(conn),
          metadata: %{requested_amount: application.requested_amount, customer_id: application.customer_id, decline_reason_category: decline_reason_category}
        )

        conn
        |> put_flash(:info, "Application rejected.")
        |> redirect(to: ~p"/admin/loans/#{application}")

      {:error, reason} ->
        conn
        |> put_flash(:error, approval_error_message(reason))
        |> redirect(to: ~p"/admin/loans/#{id}")
    end
  end

  def conditionally_approve(conn, %{"id" => id} = params) do
    application = Applications.get_application!(conn.assigns.current_scope, id)
    conditions = Map.get(params, "conditions", "")
    attestation = attests_no_conflict_of_interest?(params)

    case Applications.conditionally_approve_application(application, conn.assigns.current_scope, conditions, attestation) do
      {:ok, application} ->
        AuditLogs.log("loan_application_conditionally_approved",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "loan_application",
          target_id: application.id,
          ip_address: get_ip(conn),
          metadata: %{customer_id: application.customer_id, conditions: conditions}
        )

        conn
        |> put_flash(:info, "Application conditionally approved — conditions must be cleared before disbursement.")
        |> redirect(to: ~p"/admin/loans/#{application}")

      {:error, reason} ->
        conn
        |> put_flash(:error, approval_error_message(reason))
        |> redirect(to: ~p"/admin/loans/#{id}")
    end
  end

  def refer(conn, %{"id" => id} = params) do
    application = Applications.get_application!(conn.assigns.current_scope, id)
    reason = Map.get(params, "reason", "")

    case Applications.refer_application(application, conn.assigns.current_scope, reason) do
      {:ok, application} ->
        AuditLogs.log("loan_application_referred",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "loan_application",
          target_id: application.id,
          ip_address: get_ip(conn),
          metadata: %{customer_id: application.customer_id, reason: reason}
        )

        conn
        |> put_flash(:info, "Application referred back for more information.")
        |> redirect(to: ~p"/admin/loans/#{application}")

      {:error, reason} ->
        conn
        |> put_flash(:error, approval_error_message(reason))
        |> redirect(to: ~p"/admin/loans/#{id}")
    end
  end

  def clear_conditions(conn, %{"id" => id}) do
    application = Applications.get_application!(conn.assigns.current_scope, id)

    case Applications.clear_conditions(application, conn.assigns.current_scope) do
      {:ok, application} ->
        AuditLogs.log("loan_application_conditions_cleared",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "loan_application",
          target_id: application.id,
          ip_address: get_ip(conn),
          metadata: %{customer_id: application.customer_id}
        )

        conn
        |> put_flash(:info, "Conditions cleared — ready to disburse.")
        |> redirect(to: ~p"/admin/loans/#{application}")

      {:error, reason} ->
        conn
        |> put_flash(:error, approval_error_message(reason))
        |> redirect(to: ~p"/admin/loans/#{id}")
    end
  end

  defp attests_no_conflict_of_interest?(params) do
    Map.get(params, "conflict_of_interest_confirmed") in ["true", "on", true]
  end

  defp approval_error_message(:invalid_status), do: "This application isn't in a status that allows this action."
  defp approval_error_message(:maker_checker_violation), do: "You submitted this application — someone else must decide it."
  defp approval_error_message(:already_decided), do: "You've already recorded a decision on this application — a different person must act next."
  defp approval_error_message(:conflict_of_interest_attestation_required), do: "You must confirm you have no conflict of interest with this applicant."
  defp approval_error_message(:exceeds_approval_limit), do: "This amount exceeds your approval limit."
  defp approval_error_message(:guarantor_required), do: "This product requires a guarantor on record before it can be approved."
  defp approval_error_message(:insufficient_approval_role), do: "This product requires a more senior role to approve."
  defp approval_error_message(:income_data_missing), do: "This product requires an affordability check, but the customer has no income data on file."
  defp approval_error_message(:affordability_exceeded), do: "This loan would exceed the product's maximum debt-to-income ratio for this customer."
  defp approval_error_message(:crb_check_required), do: "This product requires a CRB report on record before it can be approved."
  defp approval_error_message(:adverse_crb_report), do: "This customer's most recent CRB report is adverse."
  defp approval_error_message(:crb_check_expired), do: "This customer's CRB report is more than 90 days old — a fresh check is required."
  defp approval_error_message(:conditions_not_cleared), do: "This application's conditions must be cleared before it can be disbursed."
  defp approval_error_message(:no_conditions_to_clear), do: "This application has no outstanding conditions to clear."
  defp approval_error_message(%Ecto.Changeset{} = changeset), do: "Could not complete this action: #{changeset_error_summary(changeset)}"
  defp approval_error_message(_), do: "Could not complete this action."

  defp changeset_error_summary(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join("; ", fn {field, errors} -> "#{field} #{Enum.join(errors, ", ")}" end)
  end

  def disburse(conn, %{"id" => id} = params) do
    application = Applications.get_application!(conn.assigns.current_scope, id)
    disbursement_details = params |> Map.take(["method", "reference"]) |> Map.put_new("method", "bank_transfer")

    case Applications.disburse_application(application, conn.assigns.current_scope, disbursement_details) do
      {:ok, application, account} ->
        AuditLogs.log("loan_application_disbursed",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "loan_account",
          target_id: account.id,
          ip_address: get_ip(conn),
          metadata: %{
            principal_amount: account.principal_amount,
            customer_id: account.customer_id,
            contract_reference: account.contract_reference,
            disbursement_method: account.disbursement_method
          }
        )

        conn
        |> put_flash(:info, "Application disbursed — account #{account.contract_reference} opened.")
        |> redirect(to: ~p"/admin/loans/#{application}")

      {:error, :invalid_status} ->
        conn
        |> put_flash(:error, "This application isn't approved yet — it can't be disbursed.")
        |> redirect(to: ~p"/admin/loans/#{id}")

      {:error, :conditions_not_cleared} ->
        conn
        |> put_flash(:error, "This application's conditions must be cleared before it can be disbursed.")
        |> redirect(to: ~p"/admin/loans/#{id}")

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_flash(:error, "Could not disburse application: #{changeset_error_summary(changeset)}")
        |> redirect(to: ~p"/admin/loans/#{id}")

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not disburse application.")
        |> redirect(to: ~p"/admin/loans/#{id}")
    end
  end

  def reverse_disbursement(conn, %{"id" => id} = params) do
    scope = conn.assigns.current_scope
    application = Applications.get_application!(scope, id)
    account = application.loan_account
    reason = Map.get(params, "reason", "")

    case Lending.reverse_disbursement(account, conn.assigns.current_user.id, reason) do
      {:ok, reversed_account} ->
        AuditLogs.log("loan_account_disbursement_reversed",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "loan_account",
          target_id: reversed_account.id,
          ip_address: get_ip(conn),
          metadata: %{contract_reference: reversed_account.contract_reference, reason: reason}
        )

        conn
        |> put_flash(:info, "Disbursement reversed.")
        |> redirect(to: ~p"/admin/loans/#{application}")

      {:error, :invalid_status} ->
        conn
        |> put_flash(:error, "This loan account isn't active — its disbursement can't be reversed.")
        |> redirect(to: ~p"/admin/loans/#{id}")

      {:error, :payments_already_received} ->
        conn
        |> put_flash(:error, "This loan already has payments recorded against it — its disbursement can no longer be reversed.")
        |> redirect(to: ~p"/admin/loans/#{id}")

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not reverse this disbursement.")
        |> redirect(to: ~p"/admin/loans/#{id}")
    end
  end

  def withdraw(conn, %{"id" => id}) do
    application = Applications.get_application!(conn.assigns.current_scope, id)

    case Applications.withdraw_application(application, conn.assigns.current_scope) do
      {:ok, application} ->
        AuditLogs.log("loan_application_withdrawn",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "loan_application",
          target_id: application.id,
          ip_address: get_ip(conn),
          metadata: %{customer_id: application.customer_id}
        )

        conn
        |> put_flash(:info, "Application withdrawn.")
        |> redirect(to: ~p"/admin/loans/#{application}")

      {:error, :invalid_status} ->
        conn
        |> put_flash(:error, "This application has already been decided — it can't be withdrawn.")
        |> redirect(to: ~p"/admin/loans/#{id}")

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not withdraw application.")
        |> redirect(to: ~p"/admin/loans/#{id}")
    end
  end

  def create_payment(conn, %{"id" => id, "payment" => payment_params}) do
    scope = conn.assigns.current_scope
    application = Applications.get_application!(scope, id)
    account = application.loan_account

    if is_nil(account) do
      conn
      |> put_flash(:error, "This application has no loan account yet — disburse it first.")
      |> redirect(to: ~p"/admin/loans/#{application}")
    else
      params =
        payment_params
        |> Map.put("received_at", date_param_to_datetime(payment_params["received_at"]))
        |> Map.put("loan_account_id", account.id)
        |> Map.put("recorded_by_id", conn.assigns.current_user.id)

      case Payments.record_payment(scope, params) do
        {:ok, transaction} ->
          AuditLogs.log("payment_recorded",
            actor_id: conn.assigns.current_user.id,
            actor_email: conn.assigns.current_user.email,
            target_type: "payment_transaction",
            target_id: transaction.id,
            ip_address: get_ip(conn),
            metadata: %{amount: transaction.amount, loan_account_id: account.id}
          )

          conn
          |> put_flash(:info, payment_recorded_message(transaction))
          |> redirect(to: ~p"/admin/loans/#{application}")

        {:error, changeset} ->
          render_show_with_errors(conn, application, payment_changeset: changeset)
      end
    end
  end

  defp payment_recorded_message(%{overpayment_amount: overpayment}) do
    if overpayment && Decimal.compare(overpayment, Decimal.new("0")) == :gt do
      "Payment recorded — ZMW #{overpayment} was in excess of the outstanding balance and was not applied."
    else
      "Payment recorded successfully."
    end
  end

  def record_failed_payment(conn, %{"id" => id, "payment" => payment_params}) do
    scope = conn.assigns.current_scope
    application = Applications.get_application!(scope, id)
    account = application.loan_account

    if is_nil(account) do
      conn
      |> put_flash(:error, "This application has no loan account yet — disburse it first.")
      |> redirect(to: ~p"/admin/loans/#{application}")
    else
      params =
        payment_params
        |> Map.put("received_at", date_param_to_datetime(payment_params["received_at"]))
        |> Map.put("loan_account_id", account.id)
        |> Map.put("recorded_by_id", conn.assigns.current_user.id)

      case Payments.record_failed_payment(scope, params) do
        {:ok, transaction} ->
          AuditLogs.log("payment_failed",
            actor_id: conn.assigns.current_user.id,
            actor_email: conn.assigns.current_user.email,
            target_type: "payment_transaction",
            target_id: transaction.id,
            ip_address: get_ip(conn),
            metadata: %{amount: transaction.amount, loan_account_id: account.id, fail_reason: transaction.fail_reason}
          )

          conn
          |> put_flash(:info, "Failed payment attempt logged.")
          |> redirect(to: ~p"/admin/loans/#{application}")

        {:error, changeset} ->
          render_show_with_errors(conn, application, failed_payment_changeset: changeset)
      end
    end
  end

  def void_payment(conn, %{"id" => id, "transaction_id" => transaction_id} = params) do
    scope = conn.assigns.current_scope
    application = Applications.get_application!(scope, id)
    transaction = Payments.get_transaction!(scope, transaction_id)
    reason = Map.get(params, "reason", "Not specified")

    case transaction.status do
      "posted" ->
        attrs = %{"voided_by_id" => conn.assigns.current_user.id, "void_reason" => reason}

        case Payments.void_payment(transaction, attrs) do
          {:ok, voided} ->
            AuditLogs.log("payment_voided",
              actor_id: conn.assigns.current_user.id,
              actor_email: conn.assigns.current_user.email,
              target_type: "payment_transaction",
              target_id: voided.id,
              ip_address: get_ip(conn),
              metadata: %{amount: voided.amount, void_reason: reason}
            )

            conn
            |> put_flash(:info, "Payment voided.")
            |> redirect(to: ~p"/admin/loans/#{application}")

          {:error, _} ->
            conn
            |> put_flash(:error, "Could not void payment.")
            |> redirect(to: ~p"/admin/loans/#{application}")
        end

      _ ->
        conn
        |> put_flash(:error, "This payment is no longer posted (already voided or failed).")
        |> redirect(to: ~p"/admin/loans/#{application}")
    end
  end

  def fail_payment(conn, %{"id" => id, "transaction_id" => transaction_id} = params) do
    scope = conn.assigns.current_scope
    application = Applications.get_application!(scope, id)
    transaction = Payments.get_transaction!(scope, transaction_id)
    reason = Map.get(params, "reason", "Not specified")

    case transaction.status do
      "posted" ->
        attrs = %{"failed_by_id" => conn.assigns.current_user.id, "fail_reason" => reason}

        case Payments.fail_payment(transaction, attrs) do
          {:ok, failed} ->
            AuditLogs.log("payment_marked_failed",
              actor_id: conn.assigns.current_user.id,
              actor_email: conn.assigns.current_user.email,
              target_type: "payment_transaction",
              target_id: failed.id,
              ip_address: get_ip(conn),
              metadata: %{amount: failed.amount, fail_reason: reason}
            )

            conn
            |> put_flash(:info, "Payment marked as failed.")
            |> redirect(to: ~p"/admin/loans/#{application}")

          {:error, _} ->
            conn
            |> put_flash(:error, "Could not mark payment as failed.")
            |> redirect(to: ~p"/admin/loans/#{application}")
        end

      _ ->
        conn
        |> put_flash(:error, "This payment is no longer posted (already voided or failed).")
        |> redirect(to: ~p"/admin/loans/#{application}")
    end
  end

  def receipt(conn, %{"id" => id, "transaction_id" => transaction_id}) do
    scope = conn.assigns.current_scope
    application = Applications.get_application!(scope, id)
    transaction = Payments.get_transaction!(scope, transaction_id) |> Repo.preload(:recorded_by)
    organisation = Organisations.get_organisation!(application.organisation_id)

    conn
    |> put_layout(html: false)
    |> render(:receipt, application: application, transaction: transaction, organisation: organisation)
  end

  def create_collateral(conn, %{"id" => id, "collateral" => collateral_params}) do
    application = Applications.get_application!(conn.assigns.current_scope, id)
    account = application.loan_account

    case Applications.create_collateral(account, collateral_params) do
      {:ok, collateral} ->
        AuditLogs.log("collateral_added",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "collateral",
          target_id: collateral.id,
          ip_address: get_ip(conn),
          metadata: %{type: collateral.type, estimated_value: collateral.estimated_value, loan_account_id: account.id}
        )

        conn
        |> put_flash(:info, "Collateral recorded.")
        |> redirect(to: ~p"/admin/loans/#{application}")

      {:error, changeset} ->
        render_show_with_errors(conn, application, collateral_changeset: changeset)
    end
  end

  def delete_collateral(conn, %{"id" => id, "collateral_id" => collateral_id}) do
    scope = conn.assigns.current_scope
    application = Applications.get_application!(scope, id)
    collateral = Applications.get_collateral!(scope, collateral_id)

    {:ok, _} = Applications.delete_collateral(collateral)

    AuditLogs.log("collateral_removed",
      actor_id: conn.assigns.current_user.id,
      actor_email: conn.assigns.current_user.email,
      target_type: "collateral",
      target_id: collateral.id,
      ip_address: get_ip(conn),
      metadata: %{type: collateral.type, estimated_value: collateral.estimated_value}
    )

    conn
    |> put_flash(:info, "Collateral removed.")
    |> redirect(to: ~p"/admin/loans/#{application}")
  end

  # Re-renders the application show page with every assign it needs,
  # overriding just the one changeset that failed validation — used by
  # both create_payment and create_collateral's error branches so a bad
  # submission never crashes on a missing assign.
  defp render_show_with_errors(conn, application, overrides) do
    scope = conn.assigns.current_scope
    application = Applications.get_application!(scope, application.id)
    fraud_signals = Applications.fraud_signals(application)

    {account, interest, installments, transactions, collaterals, days_past_due} =
      case application.loan_account do
        nil -> {nil, nil, [], [], [], 0}
        account ->
          {account, Lending.compound_interest_details(account),
           Lending.list_installments_for_account(scope, account.id),
           Payments.list_transactions_for_account(scope, account.id),
           Applications.list_collaterals_for_account(scope, account.id),
           Lending.days_past_due(account)}
      end

    assigns =
      [
        application: application,
        account: account,
        interest: interest,
        installments: installments,
        transactions: transactions,
        payment_changeset: PaymentTransaction.changeset(%PaymentTransaction{}, %{}),
        failed_payment_changeset: PaymentTransaction.failed_attempt_changeset(%PaymentTransaction{}, %{}),
        collateral_changeset: Collateral.changeset(%Collateral{}, %{}),
        collaterals: collaterals,
        fraud_signals: fraud_signals,
        days_past_due: days_past_due
      ]
      |> Keyword.merge(overrides)

    render(conn, :show, assigns)
  end

  # The payment form submits a plain date (<input type="date">); the
  # schema stores a full :utc_datetime, so this fills in a time
  # component (the account's local "now") before casting.
  defp date_param_to_datetime(nil), do: nil
  defp date_param_to_datetime(""), do: nil

  defp date_param_to_datetime(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        now = DateTime.utc_now()
        DateTime.new!(date, DateTime.to_time(now), "Etc/UTC")

      {:error, _} ->
        date_string
    end
  end

  defp get_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end
