defmodule LoanSystem.ReportsTest do
  use ExUnit.Case
  doctest LoanSystem.Reports

  alias LoanSystem.Loans.Loan
  alias LoanSystem.Payments.Payment
  alias LoanSystem.Reports
  alias LoanSystem.Reports.LoanReport

  # We need to temporarily handle the missing PaymentProcessor.get_loan_internal function
  # that's used by the Reports module. In a real implementation, you would use a proper
  # mocking library like Mox.
  
  # For this test file, we'll add a temporary implementation by redefining the module
  defmodule LoanSystem.Payments.PaymentProcessor do
    def get_loan_internal("loan_test_123") do
      {:ok, %Loan{
        id: "loan_test_123",
        client_id: "client_test_456",
        amount: Decimal.new("10000.00"),
        interest_rate: Decimal.new("12.0"),
        term_months: 12,
        status: :active,
        approved_at: ~U[2023-01-01 12:00:00Z],
        next_payment_date: ~D[2023-02-01],
        remaining_balance: Decimal.new("10000.00"),
        created_at: ~U[2022-12-30 10:00:00Z],
        updated_at: ~U[2023-01-01 12:00:00Z]
      }}
    end

    def get_loan_internal("loan_test_789") do
      {:ok, %Loan{
        id: "loan_test_789",
        client_id: "client_test_456",
        amount: Decimal.new("5000.00"),
        interest_rate: Decimal.new("10.0"),
        term_months: 6,
        status: :completed,
        approved_at: ~U[2022-07-01 12:00:00Z],
        next_payment_date: nil,
        remaining_balance: Decimal.new("0.00"),
        created_at: ~U[2022-06-28 10:00:00Z],
        updated_at: ~U[2022-12-20 15:30:00Z]
      }}
    end

    def get_loan_internal(_) do
      {:error, :loan_not_found}
    end

    def get_payment_history("loan_test_123") do
      {:ok, [
        %Payment{
          id: "payment_test_001",
          loan_id: "loan_test_123",
          amount: Decimal.new("900.00"),
          payment_date: ~U[2023-02-01 10:30:00Z],
          status: :processed,
          created_at: ~U[2023-02-01 10:30:00Z],
          updated_at: ~U[2023-02-01 10:30:00Z]
        },
        %Payment{
          id: "payment_test_002",
          loan_id: "loan_test_123",
          amount: Decimal.new("900.00"),
          payment_date: ~U[2023-03-03 14:45:00Z],
          status: :processed,
          created_at: ~U[2023-03-03 14:45:00Z],
          updated_at: ~U[2023-03-03 14:45:00Z]
        }
      ]}
    end

    def get_payment_history(_) do
      {:ok, []}
    end

    def calculate_next_payment_date(%Loan{next_payment_date: date}) when not is_nil(date) do
      {:ok, date}
    end

    def calculate_next_payment_date(%Loan{status: :completed}) do
      {:ok, nil}
    end

    def calculate_next_payment_date(_) do
      {:ok, Date.add(Date.utc_today(), 30)}
    end
  end

  # Setup test data
  setup do
    # This is for when we're not using the mocked function above
    standard_loan = %Loan{
      id: "loan_test_123",
      client_id: "client_test_456",
      amount: Decimal.new("10000.00"),
      interest_rate: Decimal.new("12.0"),
      term_months: 12,
      status: :active,
      approved_at: ~U[2023-01-01 12:00:00Z],
      next_payment_date: ~D[2023-02-01],
      remaining_balance: Decimal.new("10000.00"),
      created_at: ~U[2022-12-30 10:00:00Z],
      updated_at: ~U[2023-01-01 12:00:00Z]
    }

    completed_loan = %Loan{
      id: "loan_test_789",
      client_id: "client_test_456",
      amount: Decimal.new("5000.00"),
      interest_rate: Decimal.new("10.0"),
      term_months: 6,
      status: :completed,
      approved_at: ~U[2022-07-01 12:00:00Z],
      next_payment_date: nil,
      remaining_balance: Decimal.new("0.00"),
      created_at: ~U[2022-06-28 10:00:00Z],
      updated_at: ~U[2022-12-20 15:30:00Z]
    }

    %{
      standard_loan: standard_loan,
      completed_loan: completed_loan,
      test_loan_id: "loan_test_123",
      completed_loan_id: "loan_test_789",
      invalid_loan_id: "loan_does_not_exist",
      test_client_id: "client_test_456"
    }
  end

  describe "get_loan_report/1" do
    test "generates a comprehensive loan report", %{test_loan_id: loan_id} do
      {:ok, report} = Reports.get_loan_report(loan_id)

      # Check that report has all required sections
      assert Map.has_key?(report, :summary)
      assert Map.has_key?(report, :schedule)
      assert Map.has_key?(report, :history)

      # Check summary content
      assert report.summary.loan_id == loan_id
      assert report.summary.status == :active

      # Check schedule content
      assert is_list(report.schedule)
      assert length(report.schedule) > 0
      assert Enum.all?(report.schedule, &(Map.has_key?(&1, :payment_number)))

      # Check history content
      assert is_list(report.history)
      assert Enum.all?(report.history, &(Map.has_key?(&1, :payment_id)))
    end

    test "returns error for invalid loan ID", %{invalid_loan_id: loan_id} do
      assert {:error, message} = Reports.get_loan_report(loan_id)
      assert is_binary(message)
      assert String.contains?(message, loan_id)
    end
  end

  describe "get_loan_summary/1" do
    test "gets loan summary by ID", %{test_loan_id: loan_id} do
      {:ok, summary} = Reports.get_loan_summary(loan_id)

      assert summary.loan_id == loan_id
      assert Decimal.equal?(summary.loan_amount, Decimal.new("10000.00"))
      assert summary.status == :active
    end

    test "gets loan summary for loan struct", %{standard_loan: loan} do
      {:ok, summary} = Reports.get_loan_summary(loan)

      assert summary.loan_id == loan.id
      assert Decimal.equal?(summary.loan_amount, loan.amount)
      assert summary.status == loan.status
    end

    test "returns error for invalid loan ID", %{invalid_loan_id: loan_id} do
      assert {:error, message} = Reports.get_loan_summary(loan_id)
      assert is_binary(message)
    end
  end

  describe "get_payment_schedule/1" do
    test "gets payment schedule by ID", %{test_loan_id: loan_id} do
      {:ok, schedule} = Reports.get_payment_schedule(loan_id)

      assert is_list(schedule)
      assert length(schedule) > 0
      assert Enum.at(schedule, 0).payment_number == 1
    end

    test "gets payment schedule for loan struct", %{standard_loan: loan} do
      {:ok, schedule} = Reports.get_payment_schedule(loan)

      assert is_list(schedule)
      assert length(schedule) == loan.term_months
    end

    test "returns error for invalid loan ID", %{invalid_loan_id: loan_id} do
      assert {:error, message} = Reports.get_payment_schedule(loan_id)
      assert is_binary(message)
    end
  end

  describe "get_payment_history/1" do
    test "gets payment history by ID", %{test_loan_id: loan_id} do
      {:ok, history} = Reports.get_payment_history(loan_id)

      assert is_list(history)
      assert length(history) > 0
      assert Enum.all?(history, &(Map.has_key?(&1, :payment_id)))
    end

    test "returns error for invalid loan ID", %{invalid_loan_id: loan_id} do
      assert {:error, message} = Reports.get_payment_history(loan_id)
      assert is_binary(message)
    end
  end

  describe "get_client_loans/1" do
    test "gets all loans for a client", %{test_client_id: client_id} do
      {:ok, loans} = Reports.get_client_loans(client_id)

      assert is_list(loans)
      assert length(loans) > 0
      assert Enum.all?(loans, &(Map.has_key?(&1, :loan_id)))
      assert Enum.all?(loans, &(Map.has_key?(&1, :loan_amount)))
      assert Enum.all?(loans, &(Map.has_key?(&1, :status)))
    end
  end

  describe "get_payments_due/1" do
    test "gets payments due within a date range" do
      # Create a date range for the next 30 days
      today = Date.utc_today()
      date_range = %{from: today, to: Date.add(today, 30)}

      {:ok, due_payments} = Reports.get_payments_due(date_range)

      assert is_list(due_payments)
      assert Enum.all?(due_payments, &(Map.has_key?(&1, :due_date)))
      assert Enum.all?(due_payments, &(Map.has_key?(&1, :loan_id)))
      assert Enum.all?(due_payments, &(Map.has_key?(&1, :client_id)))
      assert Enum.all?(due_payments, &(Map.has_key?(&1, :payment_amount)))

      # Check that all due dates are within the specified range
      Enum.each(due_payments, fn payment ->
        assert Date.compare(payment.due_date, date_range.from) != :lt
        assert Date.compare(payment.due_date, date_range.to) != :gt
      end)
    end
  end

  describe "get_loans_by_status/1" do
    test "gets all loans with a specific status" do
      {:ok, active_loans} = Reports.get_loans_by_status(:active)
      {:ok, completed_loans} = Reports.get_loans_by_status(:completed)

      # Check active loans
      assert is_list(active_loans)
      assert Enum.all?(active_loans, &(&1.status == :active))

      # Check completed loans
      assert is_list(completed_loans)
      assert Enum.all?(completed_loans, &(&1.status == :completed))
    end
  end
end

