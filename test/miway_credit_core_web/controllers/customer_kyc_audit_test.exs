defmodule MiwayCreditCoreWeb.CustomerKycAuditTest do
  @moduledoc """
  The "KYC changes must be audited" and "NRC numbers must be protected"
  critical controls from Step 7 — as real HTTP tests. Every KYC write
  must leave an AuditLogs entry, and none of them may leak the raw
  id_number into that entry's metadata.
  """

  use MiwayCreditCoreWeb.ConnCase, async: true

  import MiwayCreditCore.{CustomersFixtures, OrganisationsFixtures}
  alias MiwayCreditCore.AuditLogs
  alias MiwayCreditCore.Accounts.Scope

  setup do
    organisation = organisation_fixture()
    org_admin = staff_member_in_organisation_fixture(organisation, "organisation_administrator")
    customer = customer_fixture_in_organisation(organisation, %{id_number: "999999/12/3"})

    %{organisation: organisation, org_admin: org_admin, customer: customer}
  end

  test "creating a customer is audited and never logs the raw id_number", %{
    conn: conn,
    org_admin: org_admin,
    organisation: organisation
  } do
    conn = login(conn, org_admin)

    conn =
      post(conn, ~p"/admin/customers",
        customer: %{
          "name" => "New Customer",
          "phone" => "260970009999",
          "id_number" => "888888/12/3",
          "customer_type" => "individual",
          "id_type" => "nrc"
        }
      )

    assert redirected_to(conn) =~ ~r{^/admin/customers/}

    entry = AuditLogs.list_recent(%Scope{organisation_id: organisation.id}, 1) |> hd()
    assert entry.event == "customer_created"
    assert entry.target_type == "customer"
    refute metadata_contains?(entry, "888888/12/3")
  end

  test "adding a next of kin is audited", %{conn: conn, org_admin: org_admin, customer: customer} do
    conn = login(conn, org_admin)

    conn =
      post(conn, ~p"/admin/customers/#{customer.id}/next_of_kin",
        next_of_kin: %{"name" => "Jane", "relationship" => "Sister", "phone" => "260971111111"}
      )

    assert redirected_to(conn) == ~p"/admin/customers/#{customer.id}"

    entry = AuditLogs.list_recent(%Scope{organisation_id: customer.organisation_id}, 1) |> hd()
    assert entry.event == "next_of_kin_added"
    assert entry.target_type == "next_of_kin"
  end

  test "adding a guarantor is audited and never logs the guarantor's raw id_number", %{
    conn: conn,
    org_admin: org_admin,
    customer: customer
  } do
    conn = login(conn, org_admin)

    conn =
      post(conn, ~p"/admin/customers/#{customer.id}/guarantors",
        guarantor: %{
          "name" => "Peter",
          "relationship" => "Friend",
          "phone" => "260972222222",
          "id_type" => "nrc",
          "id_number" => "777777/12/3"
        }
      )

    assert redirected_to(conn) == ~p"/admin/customers/#{customer.id}"

    entry = AuditLogs.list_recent(%Scope{organisation_id: customer.organisation_id}, 1) |> hd()
    assert entry.event == "guarantor_added"
    assert entry.target_type == "guarantor"
    refute metadata_contains?(entry, "777777/12/3")
  end

  test "uploading a KYC document is audited and never logs file bytes or content", %{
    conn: conn,
    org_admin: org_admin,
    customer: customer
  } do
    conn = login(conn, org_admin)
    path = Path.join(System.tmp_dir!(), "audit_test_upload_#{System.unique_integer([:positive])}")
    File.write!(path, "sensitive document bytes")
    upload = %Plug.Upload{path: path, filename: "nrc.jpg", content_type: "image/jpeg"}

    conn =
      post(conn, ~p"/admin/customers/#{customer.id}/kyc_documents",
        kyc_document: %{"document_type" => "nrc_copy", "file" => upload}
      )

    assert redirected_to(conn) == ~p"/admin/customers/#{customer.id}"

    entry = AuditLogs.list_recent(%Scope{organisation_id: customer.organisation_id}, 1) |> hd()
    assert entry.event == "kyc_document_uploaded"
    assert entry.target_type == "kyc_document"
    refute metadata_contains?(entry, "sensitive document bytes")
  end

  test "an upload blocked by the malware scanner is audited and never reaches disk", %{
    conn: conn,
    org_admin: org_admin,
    customer: customer
  } do
    conn = login(conn, org_admin)

    path =
      Path.join(System.tmp_dir!(), "blocked_test_upload_#{System.unique_integer([:positive])}")

    File.write!(path, "eicar test string")
    upload = %Plug.Upload{path: path, filename: "nrc.jpg", content_type: "image/jpeg"}

    MiwayCreditCore.Customers.MalwareScanner.Test.set_result({:infected, "Test.Signature"})

    conn =
      post(conn, ~p"/admin/customers/#{customer.id}/kyc_documents",
        kyc_document: %{"document_type" => "nrc_copy", "file" => upload}
      )

    assert redirected_to(conn) == ~p"/admin/customers/#{customer.id}"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "security scan"

    entry = AuditLogs.list_recent(%Scope{organisation_id: customer.organisation_id}, 1) |> hd()
    assert entry.event == "kyc_document_scan_blocked"
    refute metadata_contains?(entry, "eicar test string")

    assert MiwayCreditCore.Customers.list_kyc_documents_for_customer(
             %Scope{organisation_id: customer.organisation_id},
             customer.id
           ) == []
  end

  test "downloading a KYC document returns the original bytes, decrypted end-to-end", %{
    conn: conn,
    org_admin: org_admin,
    customer: customer
  } do
    conn = login(conn, org_admin)

    path =
      Path.join(System.tmp_dir!(), "download_test_upload_#{System.unique_integer([:positive])}")

    original_bytes = "%PDF-1.4 the real content of this document, byte for byte"
    File.write!(path, original_bytes)
    upload = %Plug.Upload{path: path, filename: "id.pdf", content_type: "application/pdf"}

    conn =
      post(conn, ~p"/admin/customers/#{customer.id}/kyc_documents",
        kyc_document: %{"document_type" => "nrc_copy", "file" => upload}
      )

    assert redirected_to(conn) == ~p"/admin/customers/#{customer.id}"

    document =
      MiwayCreditCore.Customers.list_kyc_documents_for_customer(
        %Scope{organisation_id: customer.organisation_id},
        customer.id
      )
      |> hd()

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})
      |> login(org_admin)
      |> get(~p"/admin/customers/#{customer.id}/kyc_documents/#{document.id}/download")

    assert conn.status == 200
    assert conn.resp_body == original_bytes
  end

  test "verifying KYC is audited", %{conn: conn, org_admin: org_admin, customer: customer} do
    conn = login(conn, org_admin)
    conn = patch(conn, ~p"/admin/customers/#{customer.id}/kyc/submit")
    assert redirected_to(conn) == ~p"/admin/customers/#{customer.id}"

    conn = patch(conn, ~p"/admin/customers/#{customer.id}/kyc/verify")
    assert redirected_to(conn) == ~p"/admin/customers/#{customer.id}"

    entry = AuditLogs.list_recent(%Scope{organisation_id: customer.organisation_id}, 1) |> hd()
    assert entry.event == "kyc_verified"
    assert entry.target_type == "customer"
  end

  test "index view masks the NRC; edit view (customers.manage) shows it in full", %{
    conn: conn,
    org_admin: org_admin,
    customer: customer
  } do
    conn = login(conn, org_admin)

    index_body = conn |> get(~p"/admin/customers") |> html_response(200)
    refute index_body =~ "999999/12/3"

    edit_body = conn |> get(~p"/admin/customers/#{customer.id}/edit") |> html_response(200)
    assert edit_body =~ "999999/12/3"
  end

  defp metadata_contains?(entry, value) do
    entry.metadata
    |> Map.values()
    |> Enum.any?(&(is_binary(&1) and &1 =~ value))
  end

  defp login(conn, user) do
    conn
    |> Plug.Conn.put_session(:user_id, user.id)
    |> Plug.Conn.put_session(:authenticated_at, NaiveDateTime.utc_now())
  end
end
