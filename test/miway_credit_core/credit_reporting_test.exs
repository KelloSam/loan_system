defmodule MiwayCreditCore.CreditReportingTest do
  use MiwayCreditCore.DataCase, async: true

  import MiwayCreditCore.{CustomersFixtures, AccountsFixtures, OrganisationsFixtures}

  alias MiwayCreditCore.{CreditReporting, Customers}
  alias MiwayCreditCore.CreditReporting.ManualAdapter
  alias MiwayCreditCore.Accounts.Scope

  describe "ManualAdapter.record_report/4" do
    test "refuses without an active credit_check consent on file" do
      customer = customer_fixture()
      scope = %Scope{organisation_id: customer.organisation_id}
      admin = admin_fixture()

      assert {:error, :consent_required} =
               ManualAdapter.record_report(scope, customer, valid_report_attrs(), admin.id)
    end

    test "records a report once consent is on file" do
      customer = customer_fixture()
      scope = %Scope{organisation_id: customer.organisation_id}
      admin = admin_fixture()
      grant_credit_check_consent(customer, admin.id)

      assert {:ok, report} = ManualAdapter.record_report(scope, customer, valid_report_attrs(), admin.id)
      assert report.customer_id == customer.id
      assert report.organisation_id == customer.organisation_id
      assert report.provider == "manual"
      assert report.outcome == "clear"
      assert report.requested_by_id == admin.id
    end

    test "revoking consent afterward doesn't retroactively invalidate an already-recorded report, but blocks a new one" do
      customer = customer_fixture()
      scope = %Scope{organisation_id: customer.organisation_id}
      admin = admin_fixture()
      consent = grant_credit_check_consent(customer, admin.id)

      {:ok, _report} = ManualAdapter.record_report(scope, customer, valid_report_attrs(), admin.id)
      {:ok, _} = Customers.revoke_consent(consent)

      assert {:error, :consent_required} =
               ManualAdapter.record_report(scope, customer, valid_report_attrs(), admin.id)
    end
  end

  describe "get_latest_report_for_customer/2 and list_reports_for_customer/2" do
    test "get_latest picks the most recently checked report, not the most recently inserted" do
      customer = customer_fixture()
      scope = %Scope{organisation_id: customer.organisation_id}
      admin = admin_fixture()
      grant_credit_check_consent(customer, admin.id)

      {:ok, older} =
        ManualAdapter.record_report(scope, customer, valid_report_attrs(%{"checked_at" => "2026-01-01"}), admin.id)

      {:ok, newer} =
        ManualAdapter.record_report(scope, customer, valid_report_attrs(%{"checked_at" => "2026-06-01"}), admin.id)

      latest = CreditReporting.get_latest_report_for_customer(scope, customer.id)
      assert latest.id == newer.id
      refute latest.id == older.id

      assert CreditReporting.list_reports_for_customer(scope, customer.id) |> length() == 2
    end

    test "two reports checked on the same date break the tie by which was recorded most recently" do
      customer = customer_fixture()
      scope = %Scope{organisation_id: customer.organisation_id}
      admin = admin_fixture()
      grant_credit_check_consent(customer, admin.id)
      same_day = Date.utc_today() |> Date.to_iso8601()

      {:ok, first} =
        ManualAdapter.record_report(scope, customer, valid_report_attrs(%{"outcome" => "adverse", "checked_at" => same_day}), admin.id)

      {:ok, second} =
        ManualAdapter.record_report(scope, customer, valid_report_attrs(%{"outcome" => "clear", "checked_at" => same_day}), admin.id)

      latest = CreditReporting.get_latest_report_for_customer(scope, customer.id)
      assert latest.id == second.id
      refute latest.id == first.id
      assert latest.outcome == "clear"
    end

    test "returns nil when the customer has no report on file" do
      customer = customer_fixture()
      scope = %Scope{organisation_id: customer.organisation_id}

      assert CreditReporting.get_latest_report_for_customer(scope, customer.id) == nil
      assert CreditReporting.list_reports_for_customer(scope, customer.id) == []
    end

    test "a report in another organisation never appears" do
      organisation = organisation_fixture()
      other = organisation_fixture()
      customer = customer_fixture_in_organisation(other)
      admin = admin_fixture()
      grant_credit_check_consent(customer, admin.id)

      {:ok, _report} =
        ManualAdapter.record_report(%Scope{organisation_id: other.id}, customer, valid_report_attrs(), admin.id)

      scope = %Scope{organisation_id: organisation.id}
      assert CreditReporting.get_latest_report_for_customer(scope, customer.id) == nil
    end
  end

  defp grant_credit_check_consent(customer, recorded_by_id) do
    {:ok, consent} =
      Customers.create_consent(
        customer,
        %{"consent_type" => "credit_check", "method" => "signed_form", "granted_at" => DateTime.utc_now()},
        recorded_by_id
      )

    consent
  end

  defp valid_report_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      "outcome" => "clear",
      "checked_at" => Date.utc_today() |> Date.to_iso8601(),
      "reference_number" => "CRB-#{System.unique_integer([:positive])}"
    })
  end
end
