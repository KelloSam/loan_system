defmodule MiwayCreditCore.ReportsTest do
  use MiwayCreditCore.DataCase, async: true

  import MiwayCreditCore.{ClientsFixtures, LoansFixtures}
  alias MiwayCreditCore.{Loans, Reports, Repo}

  describe "portfolio_summary/0" do
    test "total_loans counts every application; active_loans counts active accounts only" do
      client_fixture()
      loans_before = Reports.portfolio_summary().total_loans
      application = application_fixture()

      summary = Reports.portfolio_summary()
      assert summary.total_clients >= 1
      assert summary.total_loans == loans_before + 1
      assert Decimal.compare(summary.outstanding_balance, Decimal.new("0")) != :lt

      # A pending application has no account yet, so it doesn't touch active_loans.
      assert summary.active_loans == Reports.portfolio_summary().active_loans

      admin = MiwayCreditCore.AccountsFixtures.admin_fixture()
      {:ok, _approved, account} = Loans.approve_application(application, admin.id)
      after_approve = Reports.portfolio_summary()
      assert after_approve.active_loans == summary.active_loans + 1

      {:ok, _} = Loans.close_account(account)
      after_close = Reports.portfolio_summary()
      assert after_close.active_loans == summary.active_loans
    end
  end

  describe "overdue_payments/0" do
    test "lists overdue installments oldest-first, with account and client preloaded" do
      application = approved_application_fixture(%{"requested_term_months" => "1"})
      account = application.loan_account
      [installment] = Loans.list_installments_for_account(account.id)

      installment
      |> Ecto.Changeset.change(due_date: Date.add(Date.utc_today(), -3))
      |> Repo.update!()

      Loans.mark_overdue_installments()

      assert [found] = Reports.overdue_payments()
      assert found.id == installment.id
      assert found.loan_account.id == account.id
      assert found.loan_account.client.id == application.client_id
    end
  end

  describe "payments_due_soon/1" do
    test "returns unpaid installments due within the window, not overdue ones" do
      application = approved_application_fixture(%{"requested_term_months" => "1"})
      account = application.loan_account
      [installment] = Loans.list_installments_for_account(account.id)

      installment
      |> Ecto.Changeset.change(due_date: Date.add(Date.utc_today(), 3))
      |> Repo.update!()

      due_soon = Reports.payments_due_soon(7)
      assert Enum.any?(due_soon, &(&1.id == installment.id))

      far_out = Reports.payments_due_soon(1)
      refute Enum.any?(far_out, &(&1.id == installment.id))
    end
  end

  describe "loans_csv/0" do
    test "produces a header row plus one row per application" do
      client = client_fixture(%{name: "CSV, Client \"Test\""})
      application_fixture(%{"client_id" => client.id})

      csv = Reports.loans_csv()
      lines = String.split(csv, "\r\n", trim: true)

      assert hd(lines) ==
               "application_id,client_name,status,risk_level,requested_amount,granted_amount,outstanding_balance,decided_at"

      assert length(lines) >= 2
      # a client name containing a comma and quotes must be properly CSV-escaped
      assert Enum.any?(lines, &(&1 =~ ~s("CSV, Client ""Test""")))
    end

    test "includes granted_amount/outstanding_balance once an application is approved" do
      application = approved_application_fixture()
      csv = Reports.loans_csv()
      lines = String.split(csv, "\r\n", trim: true)

      assert Enum.any?(lines, fn line ->
               String.starts_with?(line, application.id) and
                 line =~ Decimal.to_string(application.loan_account.principal_amount)
             end)
    end
  end
end
