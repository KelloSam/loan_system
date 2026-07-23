defmodule MiwayCreditCoreWeb.LoanController do
  use MiwayCreditCoreWeb, :controller

  alias MiwayCreditCore.{Loans, Clients, Repo, AuditLogs}
  alias MiwayCreditCore.Loans.{Loan, Payment, Collateral}

  def index(conn, _params) do
    loans = Loans.list_loans()
    render(conn, :index, loans: loans)
  end

  def show(conn, %{"id" => id}) do
    loan = Loans.get_loan!(id) |> Repo.preload([:client, :payments])
    interest = Loans.compound_interest_details(loan)
    payment_changeset = Payment.changeset(%Payment{}, %{})
    collateral_changeset = Collateral.changeset(%Collateral{}, %{})
    collaterals = Loans.list_collaterals_for_loan(loan.id)
    fraud_signals = Loans.fraud_signals(loan)

    render(conn, :show,
      loan: loan,
      interest: interest,
      payment_changeset: payment_changeset,
      collateral_changeset: collateral_changeset,
      collaterals: collaterals,
      fraud_signals: fraud_signals
    )
  end

  def new(conn, _params) do
    clients = Clients.list_clients()
    changeset = Loan.changeset(%Loan{}, %{})
    render(conn, :new, changeset: changeset, clients: clients)
  end

  def create(conn, %{"loan" => loan_params}) do
    # remaining_balance starts equal to the principal amount
    params = Map.put_new(loan_params, "remaining_balance", loan_params["amount"])

    case Loans.create_loan(params) do
      {:ok, loan} ->
        AuditLogs.log("loan_created",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "loan",
          target_id: loan.id,
          ip_address: get_ip(conn),
          metadata: %{amount: loan.amount, client_id: loan.client_id}
        )

        conn
        |> put_flash(:info, "Loan created successfully.")
        |> redirect(to: ~p"/admin/loans/#{loan}")

      {:error, :pending_loan_exists} ->
        conn
        |> put_flash(:error, "Blocked: this client already has a pending loan. Resolve the existing application before creating a new one.")
        |> redirect(to: ~p"/admin/loans/new")

      {:error, :rejection_cooldown} ->
        conn
        |> put_flash(:error, "Blocked: this client was rejected within the last 30 days. New applications are frozen during the cooling-off period.")
        |> redirect(to: ~p"/admin/loans/new")

      {:error, changeset} ->
        clients = Clients.list_clients()
        render(conn, :new, changeset: changeset, clients: clients)
    end
  end

  def edit(conn, %{"id" => id}) do
    loan = Loans.get_loan!(id) |> Repo.preload(:client)
    changeset = Loan.changeset(loan, %{})
    render(conn, :edit, loan: loan, changeset: changeset)
  end

  def update(conn, %{"id" => id, "loan" => loan_params}) do
    loan = Loans.get_loan!(id)

    case Loans.update_loan(loan, loan_params) do
      {:ok, loan} ->
        conn
        |> put_flash(:info, "Loan updated successfully.")
        |> redirect(to: ~p"/admin/loans/#{loan}")

      {:error, changeset} ->
        loan = Repo.preload(loan, :client)
        render(conn, :edit, loan: loan, changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    loan = Loans.get_loan!(id)

    case Loans.delete_loan(loan) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Loan deleted.")
        |> redirect(to: ~p"/admin/loans")

      {:error, _} ->
        conn
        |> put_flash(:error, "Cannot delete this loan — it may have associated payments.")
        |> redirect(to: ~p"/admin/loans/#{id}")
    end
  end

  def approve(conn, %{"id" => id}) do
    loan = Loans.get_loan!(id)

    case Loans.approve_loan(loan) do
      {:ok, loan} ->
        AuditLogs.log("loan_approved",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "loan",
          target_id: loan.id,
          ip_address: get_ip(conn),
          metadata: %{amount: loan.amount, client_id: loan.client_id}
        )

        conn
        |> put_flash(:info, "Loan approved.")
        |> redirect(to: ~p"/admin/loans/#{loan}")

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not approve loan.")
        |> redirect(to: ~p"/admin/loans/#{id}")
    end
  end

  def reject(conn, %{"id" => id}) do
    loan = Loans.get_loan!(id)

    case Loans.reject_loan(loan) do
      {:ok, loan} ->
        AuditLogs.log("loan_rejected",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "loan",
          target_id: loan.id,
          ip_address: get_ip(conn),
          metadata: %{amount: loan.amount, client_id: loan.client_id}
        )

        conn
        |> put_flash(:info, "Loan rejected.")
        |> redirect(to: ~p"/admin/loans/#{loan}")

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not reject loan.")
        |> redirect(to: ~p"/admin/loans/#{id}")
    end
  end

  def create_payment(conn, %{"id" => id, "payment" => payment_params}) do
    loan = Loans.get_loan!(id)
    params = payment_params |> Map.put("loan_id", loan.id) |> Map.put("status", "paid")

    case Loans.create_payment(params) do
      {:ok, payment} ->
        AuditLogs.log("payment_recorded",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "payment",
          target_id: payment.id,
          ip_address: get_ip(conn),
          metadata: %{amount: payment.amount, loan_id: loan.id}
        )

        conn
        |> put_flash(:info, "Payment recorded successfully.")
        |> redirect(to: ~p"/admin/loans/#{loan}")

      {:error, :amount_exceeds_balance} ->
        conn
        |> put_flash(:error, "Payment amount exceeds the remaining balance.")
        |> redirect(to: ~p"/admin/loans/#{loan}")

      {:error, changeset} ->
        render_show_with_errors(conn, loan, payment_changeset: changeset)
    end
  end

  def create_collateral(conn, %{"id" => id, "collateral" => collateral_params}) do
    loan = Loans.get_loan!(id)
    params = Map.put(collateral_params, "loan_id", loan.id)

    case Loans.create_collateral(params) do
      {:ok, collateral} ->
        AuditLogs.log("collateral_added",
          actor_id: conn.assigns.current_user.id,
          actor_email: conn.assigns.current_user.email,
          target_type: "collateral",
          target_id: collateral.id,
          ip_address: get_ip(conn),
          metadata: %{type: collateral.type, estimated_value: collateral.estimated_value, loan_id: loan.id}
        )

        conn
        |> put_flash(:info, "Collateral recorded.")
        |> redirect(to: ~p"/admin/loans/#{loan}")

      {:error, changeset} ->
        render_show_with_errors(conn, loan, collateral_changeset: changeset)
    end
  end

  def delete_collateral(conn, %{"id" => id, "collateral_id" => collateral_id}) do
    loan = Loans.get_loan!(id)
    collateral = Loans.get_collateral!(collateral_id)

    {:ok, _} = Loans.delete_collateral(collateral)

    AuditLogs.log("collateral_removed",
      actor_id: conn.assigns.current_user.id,
      actor_email: conn.assigns.current_user.email,
      target_type: "collateral",
      target_id: collateral.id,
      ip_address: get_ip(conn),
      metadata: %{type: collateral.type, estimated_value: collateral.estimated_value, loan_id: loan.id}
    )

    conn
    |> put_flash(:info, "Collateral removed.")
    |> redirect(to: ~p"/admin/loans/#{loan}")
  end

  # Re-renders the loan show page with every assign it needs, overriding
  # just the one changeset that failed validation — used by both
  # create_payment and create_collateral's error branches so a bad
  # submission never crashes on a missing assign.
  defp render_show_with_errors(conn, loan, overrides) do
    loan = Loans.get_loan!(loan.id) |> Repo.preload([:client, :payments])
    interest = Loans.compound_interest_details(loan)
    fraud_signals = Loans.fraud_signals(loan)
    collaterals = Loans.list_collaterals_for_loan(loan.id)

    assigns =
      [
        loan: loan,
        interest: interest,
        payment_changeset: Payment.changeset(%Payment{}, %{}),
        collateral_changeset: Collateral.changeset(%Collateral{}, %{}),
        collaterals: collaterals,
        fraud_signals: fraud_signals
      ]
      |> Keyword.merge(overrides)

    render(conn, :show, assigns)
  end

  defp get_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end
