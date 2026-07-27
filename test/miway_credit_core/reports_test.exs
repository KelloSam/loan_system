defmodule MiwayCreditCore.ReportsTest do
  use MiwayCreditCore.DataCase, async: true

  import MiwayCreditCore.{CustomersFixtures, LoansFixtures, OrganisationsFixtures}
  alias MiwayCreditCore.{Applications, Lending, Reports, Repo}
  alias MiwayCreditCore.Accounts.Scope

  describe "portfolio_summary/1" do
    test "total_loans counts every application; active_loans counts active accounts only" do
      organisation = organisation_fixture()
      scope = %Scope{organisation_id: organisation.id}
      customer = customer_fixture_in_organisation(organisation)

      loans_before = Reports.portfolio_summary(scope).total_loans
      application = application_fixture(%{"customer_id" => customer.id})

      summary = Reports.portfolio_summary(scope)
      assert summary.total_customers >= 1
      assert summary.total_loans == loans_before + 1
      assert Decimal.compare(summary.outstanding_balance, Decimal.new("0")) != :lt

      # A pending application has no account yet, so it doesn't touch active_loans.
      assert summary.active_loans == Reports.portfolio_summary(scope).active_loans

      admin = MiwayCreditCore.AccountsFixtures.admin_fixture()
      {:ok, _approved, account} = Applications.approve_application(application, admin.id)
      after_approve = Reports.portfolio_summary(scope)
      assert after_approve.active_loans == summary.active_loans + 1

      {:ok, _} = Lending.close_account(account)
      after_close = Reports.portfolio_summary(scope)
      assert after_close.active_loans == summary.active_loans
    end
  end

  describe "overdue_payments/1" do
    test "lists overdue installments oldest-first, with account and customer preloaded" do
      application = approved_application_fixture(%{"requested_term_months" => "1"})
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      [installment] = Lending.list_installments_for_account(scope, account.id)

      installment
      |> Ecto.Changeset.change(due_date: Date.add(Date.utc_today(), -3))
      |> Repo.update!()

      Lending.mark_overdue_installments()

      assert [found] = Reports.overdue_payments(scope)
      assert found.id == installment.id
      assert found.loan_account.id == account.id
      assert found.loan_account.customer.id == application.customer_id
    end
  end

  describe "payments_due_soon/2" do
    test "returns unpaid installments due within the window, not overdue ones" do
      application = approved_application_fixture(%{"requested_term_months" => "1"})
      scope = %Scope{organisation_id: application.organisation_id}
      account = application.loan_account
      [installment] = Lending.list_installments_for_account(scope, account.id)

      installment
      |> Ecto.Changeset.change(due_date: Date.add(Date.utc_today(), 3))
      |> Repo.update!()

      due_soon = Reports.payments_due_soon(scope, 7)
      assert Enum.any?(due_soon, &(&1.id == installment.id))

      far_out = Reports.payments_due_soon(scope, 1)
      refute Enum.any?(far_out, &(&1.id == installment.id))
    end
  end

  describe "loans_csv/1" do
    test "produces a header row plus one row per application" do
      organisation = organisation_fixture()
      scope = %Scope{organisation_id: organisation.id}
      customer = customer_fixture_in_organisation(organisation, %{name: "CSV, Customer \"Test\""})
      application_fixture(%{"customer_id" => customer.id})

      csv = Reports.loans_csv(scope)
      lines = String.split(csv, "\r\n", trim: true)

      assert hd(lines) ==
               "application_id,customer_name,status,risk_level,requested_amount,granted_amount,outstanding_balance,decided_at"

      assert length(lines) >= 2
      # a customer name containing a comma and quotes must be properly CSV-escaped
      assert Enum.any?(lines, &(&1 =~ ~s("CSV, Customer ""Test""")))
    end

    test "includes granted_amount/outstanding_balance once an application is approved" do
      application = approved_application_fixture()
      scope = %Scope{organisation_id: application.organisation_id}
      csv = Reports.loans_csv(scope)
      lines = String.split(csv, "\r\n", trim: true)

      assert Enum.any?(lines, fn line ->
               String.starts_with?(line, application.id) and
                 line =~ Decimal.to_string(application.loan_account.principal_amount)
             end)
    end
  end
end
