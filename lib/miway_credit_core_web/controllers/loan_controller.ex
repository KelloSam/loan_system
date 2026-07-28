defmodule MiwayCreditCoreWeb.LoanController do
  use MiwayCreditCoreWeb, :controller

  alias MiwayCreditCore.{Applications, Lending, Payments, Customers, AuditLogs}
  alias MiwayCreditCore.Applications.{LoanApplication, Collateral}
  alias MiwayCreditCore.Payments.PaymentTransaction
  alias MiwayCreditCoreWeb.Plugs.RequirePermissionPlug

  plug RequirePermissionPlug, "applications.view" when action in [:index, :show]
  plug RequirePermissionPlug, "applications.create" when action in [:new, :create]
  plug RequirePermissionPlug, "applications.edit" when action in [:edit, :update, :delete]
  plug RequirePermissionPlug, "applications.approve" when action == :approve
  plug RequirePermissionPlug, "applications.reject" when action == :reject
  plug RequirePermissionPlug, "payments.receive" when action == :create_payment
  plug RequirePermissionPlug, "payments.reverse" when action == :void_payment
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
    collateral_changeset = Collateral.changeset(%Collateral{}, %{})

    {account, interest, installments, transactions, collaterals} =
      case application.loan_account do
        nil ->
          {nil, nil, [], [], []}

        account ->
          {
            account,
            Lending.compound_interest_details(account),
            Lending.list_installments_for_account(scope, account.id),
            Payments.list_transactions_for_account(scope, account.id),
            Applications.list_collaterals_for_account(scope, account.id)
          }
      end

    render(conn, :show,
      application: application,
      account: account,
      interest: interest,
      installments: installments,
      transactions: transactions,
      payment_changeset: payment_changeset,
      collateral_changeset: collateral_changeset,
      collaterals: collaterals,
      fraud_signals: fraud_signals
    )
  end

  def new(conn, _params) do
    customers = Customers.list_customers(conn.assigns.current_scope)
    changeset = LoanApplication.changeset(%LoanApplication{}, %{})
    render(conn, :new, changeset: changeset, customers: customers)
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

      {:error, changeset} ->
        customers = Customers.list_customers(conn.assigns.current_scope)
        render(conn, :new, changeset: changeset, customers: customers)
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

  def approve(conn, %{"id" => id}) do
    application = Applications.get_application!(conn.assigns.current_scope, id)

    case Applications.approve_application(application, conn.assigns.current_scope) do
      {:ok, application, account} ->
        AuditLogs.log("loan_application_approved",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "loan_account",
          target_id: account.id,
          ip_address: get_ip(conn),
          metadata: %{principal_amount: account.principal_amount, customer_id: account.customer_id}
        )

        conn
        |> put_flash(:info, "Application approved — account opened.")
        |> redirect(to: ~p"/admin/loans/#{application}")

      {:error, :maker_checker_violation} ->
        conn
        |> put_flash(:error, "You submitted this application — someone else must decide it.")
        |> redirect(to: ~p"/admin/loans/#{id}")

      {:error, :exceeds_approval_limit} ->
        conn
        |> put_flash(:error, "This amount exceeds your approval limit.")
        |> redirect(to: ~p"/admin/loans/#{id}")

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not approve application.")
        |> redirect(to: ~p"/admin/loans/#{id}")
    end
  end

  def reject(conn, %{"id" => id} = params) do
    application = Applications.get_application!(conn.assigns.current_scope, id)
    reason = Map.get(params, "reason", "Not specified")

    case Applications.reject_application(application, conn.assigns.current_scope, reason) do
      {:ok, application} ->
        AuditLogs.log("loan_application_rejected",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "loan_application",
          target_id: application.id,
          ip_address: get_ip(conn),
          metadata: %{requested_amount: application.requested_amount, customer_id: application.customer_id}
        )

        conn
        |> put_flash(:info, "Application rejected.")
        |> redirect(to: ~p"/admin/loans/#{application}")

      {:error, :maker_checker_violation} ->
        conn
        |> put_flash(:error, "You submitted this application — someone else must decide it.")
        |> redirect(to: ~p"/admin/loans/#{id}")

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not reject application.")
        |> redirect(to: ~p"/admin/loans/#{id}")
    end
  end

  def create_payment(conn, %{"id" => id, "payment" => payment_params}) do
    scope = conn.assigns.current_scope
    application = Applications.get_application!(scope, id)
    account = application.loan_account

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
        |> put_flash(:info, "Payment recorded successfully.")
        |> redirect(to: ~p"/admin/loans/#{application}")

      {:error, :amount_exceeds_balance} ->
        conn
        |> put_flash(:error, "Payment amount exceeds the outstanding balance.")
        |> redirect(to: ~p"/admin/loans/#{application}")

      {:error, changeset} ->
        render_show_with_errors(conn, application, payment_changeset: changeset)
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
        |> put_flash(:error, "This payment has already been voided.")
        |> redirect(to: ~p"/admin/loans/#{application}")
    end
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

    {account, interest, installments, transactions, collaterals} =
      case application.loan_account do
        nil -> {nil, nil, [], [], []}
        account ->
          {account, Lending.compound_interest_details(account),
           Lending.list_installments_for_account(scope, account.id),
           Payments.list_transactions_for_account(scope, account.id),
           Applications.list_collaterals_for_account(scope, account.id)}
      end

    assigns =
      [
        application: application,
        account: account,
        interest: interest,
        installments: installments,
        transactions: transactions,
        payment_changeset: PaymentTransaction.changeset(%PaymentTransaction{}, %{}),
        collateral_changeset: Collateral.changeset(%Collateral{}, %{}),
        collaterals: collaterals,
        fraud_signals: fraud_signals
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
