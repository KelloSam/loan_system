defmodule MiwayCreditCore.CustomersKycTest do
  use MiwayCreditCore.DataCase, async: true

  import MiwayCreditCore.{CustomersFixtures, OrganisationsFixtures, AccountsFixtures}
  alias MiwayCreditCore.Customers
  alias MiwayCreditCore.Accounts.Scope

  defp build_upload(content, filename \\ "id.jpg") do
    build_upload(content, filename, "image/jpeg")
  end

  defp build_upload(content, filename, content_type) do
    path = Path.join(System.tmp_dir!(), "upload_test_#{System.unique_integer([:positive])}")
    File.write!(path, content)
    %Plug.Upload{path: path, filename: filename, content_type: content_type}
  end

  describe "customer_type / id_type validation" do
    test "individual + nrc is valid" do
      scope = %Scope{organisation_id: organisation_fixture().id}
      attrs = valid_customer_attrs(%{customer_type: "individual", id_type: "nrc"})
      assert {:ok, _} = Customers.create_customer(scope, attrs)
    end

    test "individual + passport is valid" do
      scope = %Scope{organisation_id: organisation_fixture().id}
      attrs = valid_customer_attrs(%{customer_type: "individual", id_type: "passport"})
      assert {:ok, _} = Customers.create_customer(scope, attrs)
    end

    test "business + company_registration is valid" do
      scope = %Scope{organisation_id: organisation_fixture().id}
      attrs = valid_customer_attrs(%{customer_type: "business", id_type: "company_registration"})
      assert {:ok, _} = Customers.create_customer(scope, attrs)
    end

    test "individual + company_registration is rejected" do
      scope = %Scope{organisation_id: organisation_fixture().id}
      attrs = valid_customer_attrs(%{customer_type: "individual", id_type: "company_registration"})
      assert {:error, changeset} = Customers.create_customer(scope, attrs)
      assert "does not match customer_type" in errors_on(changeset).id_type
    end

    test "business + nrc is rejected" do
      scope = %Scope{organisation_id: organisation_fixture().id}
      attrs = valid_customer_attrs(%{customer_type: "business", id_type: "nrc"})
      assert {:error, changeset} = Customers.create_customer(scope, attrs)
      assert "does not match customer_type" in errors_on(changeset).id_type
    end

    test "an unknown customer_type is rejected" do
      scope = %Scope{organisation_id: organisation_fixture().id}
      attrs = valid_customer_attrs(%{customer_type: "alien"})
      assert {:error, changeset} = Customers.create_customer(scope, attrs)
      assert errors_on(changeset).customer_type
    end
  end

  describe "org-scoped duplicate detection (the unique-index bug fix)" do
    test "find_potential_duplicates/2 finds a same-organisation match on id_number" do
      organisation = organisation_fixture()
      existing = customer_fixture_in_organisation(organisation)
      scope = %Scope{organisation_id: organisation.id}

      matches = Customers.find_potential_duplicates(scope, %{"id_number" => existing.id_number})
      assert Enum.any?(matches, &(&1.id == existing.id))
    end

    test "find_potential_duplicates/2 never returns a different organisation's customer" do
      org_a = organisation_fixture()
      org_b = organisation_fixture()
      existing = customer_fixture_in_organisation(org_a)
      scope_b = %Scope{organisation_id: org_b.id}

      assert Customers.find_potential_duplicates(scope_b, %{"id_number" => existing.id_number}) == []
    end

    test "the same NRC can belong to customers in two different organisations" do
      org_a = organisation_fixture()
      org_b = organisation_fixture()
      shared_id_number = valid_customer_id_number()

      assert {:ok, _} =
               Customers.create_customer(%Scope{organisation_id: org_a.id}, valid_customer_attrs(%{id_number: shared_id_number}))

      assert {:ok, _} =
               Customers.create_customer(%Scope{organisation_id: org_b.id}, valid_customer_attrs(%{id_number: shared_id_number}))
    end

    test "the same NRC is still blocked within one organisation" do
      scope = %Scope{organisation_id: organisation_fixture().id}
      attrs = valid_customer_attrs()
      assert {:ok, _} = Customers.create_customer(scope, attrs)

      dup = valid_customer_attrs(%{id_number: attrs.id_number})
      assert {:error, changeset} = Customers.create_customer(scope, dup)
      assert "has already been taken" in errors_on(changeset).id_number
    end
  end

  describe "mask_id_number/1" do
    test "masks all but the last 4 characters" do
      assert Customers.mask_id_number("123456/78/9") == "*******78/9"
    end

    test "masks short values entirely" do
      assert Customers.mask_id_number("123") == "***"
    end

    test "nil passes through" do
      assert Customers.mask_id_number(nil) == nil
    end
  end

  describe "next of kin" do
    test "create/list/get/delete are org-scoped and derive organisation_id from the customer" do
      customer = customer_fixture()
      scope = %Scope{organisation_id: customer.organisation_id}

      assert {:ok, nok} =
               Customers.create_next_of_kin(customer, %{name: "Jane", relationship: "Sister", phone: "260971111111"})

      assert nok.organisation_id == customer.organisation_id
      assert nok.customer_id == customer.id
      assert [found] = Customers.list_next_of_kins_for_customer(scope, customer.id)
      assert found.id == nok.id
      assert Customers.get_next_of_kin!(scope, nok.id).id == nok.id

      assert {:ok, _} = Customers.delete_next_of_kin(nok)
      assert Customers.list_next_of_kins_for_customer(scope, customer.id) == []
    end

    test "another organisation cannot fetch it, even by a known id" do
      customer = customer_fixture()
      {:ok, nok} = Customers.create_next_of_kin(customer, %{name: "Jane", relationship: "Sister", phone: "260971111111"})

      other_scope = %Scope{organisation_id: organisation_fixture().id}
      assert_raise Ecto.NoResultsError, fn -> Customers.get_next_of_kin!(other_scope, nok.id) end
    end
  end

  describe "guarantors" do
    test "create/list/get/delete are org-scoped and require a matching id_type" do
      customer = customer_fixture()
      scope = %Scope{organisation_id: customer.organisation_id}

      attrs = %{name: "Peter", relationship: "Friend", phone: "260972222222", id_type: "nrc", id_number: "111111/11/1"}
      assert {:ok, guarantor} = Customers.create_guarantor(customer, attrs)
      assert guarantor.organisation_id == customer.organisation_id

      assert [found] = Customers.list_guarantors_for_customer(scope, customer.id)
      assert found.id == guarantor.id
      assert Customers.get_guarantor!(scope, guarantor.id).id == guarantor.id

      assert {:ok, _} = Customers.delete_guarantor(guarantor)
      assert Customers.list_guarantors_for_customer(scope, customer.id) == []
    end

    test "an invalid id_type is rejected" do
      customer = customer_fixture()
      attrs = %{name: "Peter", relationship: "Friend", phone: "260972222222", id_type: "made_up", id_number: "1"}
      assert {:error, changeset} = Customers.create_guarantor(customer, attrs)
      assert errors_on(changeset).id_type
    end

    test "another organisation cannot fetch it, even by a known id" do
      customer = customer_fixture()
      attrs = %{name: "Peter", relationship: "Friend", phone: "260972222222", id_type: "nrc", id_number: "111111/11/1"}
      {:ok, guarantor} = Customers.create_guarantor(customer, attrs)

      other_scope = %Scope{organisation_id: organisation_fixture().id}
      assert_raise Ecto.NoResultsError, fn -> Customers.get_guarantor!(other_scope, guarantor.id) end
    end
  end

  describe "kyc documents" do
    test "create stores the file on disk and records metadata; remove marks removed but keeps the file" do
      customer = customer_fixture()
      admin = admin_fixture()
      upload = build_upload("hello world")

      assert {:ok, document} = Customers.create_kyc_document(customer, upload, "nrc_copy", admin.id)
      assert document.status == "active"
      assert document.organisation_id == customer.organisation_id

      path = Customers.kyc_document_path(document)
      assert File.exists?(path)
      assert File.read!(path) == "hello world"

      assert {:ok, removed} = Customers.remove_kyc_document(document)
      assert removed.status == "removed"
      assert File.exists?(Customers.kyc_document_path(removed))
    end

    test "an invalid document_type is rejected and the just-stored file is cleaned up, not left orphaned" do
      customer = customer_fixture()
      admin = admin_fixture()
      upload = build_upload("data")

      assert {:error, changeset} = Customers.create_kyc_document(customer, upload, "not_a_real_type", admin.id)
      assert errors_on(changeset).document_type

      upload_dir =
        MiwayCreditCore.Customers.DocumentStorage.read_path(customer.organisation_id, customer.id, "placeholder")
        |> Path.dirname()

      assert File.ls!(upload_dir) == []
    end

    test "another organisation cannot fetch it, even by a known id" do
      customer = customer_fixture()
      admin = admin_fixture()
      upload = build_upload("secret")
      {:ok, document} = Customers.create_kyc_document(customer, upload, "nrc_copy", admin.id)

      other_scope = %Scope{organisation_id: organisation_fixture().id}
      assert_raise Ecto.NoResultsError, fn -> Customers.get_kyc_document!(other_scope, document.id) end
    end

    test "an unsupported content_type is rejected and the just-stored file is cleaned up" do
      customer = customer_fixture()
      admin = admin_fixture()
      upload = build_upload("MZ...fake executable bytes", "malware.exe", "application/x-msdownload")

      assert {:error, changeset} = Customers.create_kyc_document(customer, upload, "nrc_copy", admin.id)
      assert errors_on(changeset).content_type

      upload_dir =
        MiwayCreditCore.Customers.DocumentStorage.read_path(customer.organisation_id, customer.id, "placeholder")
        |> Path.dirname()

      assert File.ls!(upload_dir) == []
    end

    test "a real PDF upload still succeeds" do
      customer = customer_fixture()
      admin = admin_fixture()
      upload = build_upload("%PDF-1.4 fake but whitelisted content", "id.pdf", "application/pdf")

      assert {:ok, document} = Customers.create_kyc_document(customer, upload, "nrc_copy", admin.id)
      assert document.content_type == "application/pdf"
    end

    test "an oversized upload is rejected by the changeset" do
      attrs = %{
        organisation_id: Ecto.UUID.generate(),
        customer_id: Ecto.UUID.generate(),
        document_type: "nrc_copy",
        stored_filename: "big.pdf",
        original_filename: "big.pdf",
        content_type: "application/pdf",
        size_bytes: 10_000_001,
        status: "active",
        uploaded_by_id: admin_fixture().id,
        uploaded_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      changeset = MiwayCreditCore.Customers.KycDocument.changeset(%MiwayCreditCore.Customers.KycDocument{}, attrs)
      refute changeset.valid?
      assert changeset.errors[:size_bytes]
    end
  end

  describe "consents" do
    test "create/revoke and has_active_consent?/3" do
      customer = customer_fixture()
      admin = admin_fixture()
      scope = %Scope{organisation_id: customer.organisation_id}

      refute Customers.has_active_consent?(scope, customer.id, "credit_check")

      assert {:ok, consent} =
               Customers.create_consent(customer, %{"consent_type" => "credit_check", "method" => "digital"}, admin.id)

      assert consent.organisation_id == customer.organisation_id
      assert Customers.has_active_consent?(scope, customer.id, "credit_check")

      assert {:ok, revoked} = Customers.revoke_consent(consent)
      refute is_nil(revoked.revoked_at)
      refute Customers.has_active_consent?(scope, customer.id, "credit_check")
    end
  end

  describe "kyc status transitions" do
    test "submit_for_kyc_review/2 moves not_started -> pending_review" do
      customer = customer_fixture()
      assert customer.kyc_status == "not_started"

      scope = %Scope{user: admin_fixture(), organisation_id: customer.organisation_id}
      assert {:ok, updated} = Customers.submit_for_kyc_review(customer, scope)
      assert updated.kyc_status == "pending_review"
    end

    test "mark_kyc_verified/2 sets verified, a timestamp, and the verifying user" do
      customer = customer_fixture()
      admin = admin_fixture()
      scope = %Scope{user: admin, organisation_id: customer.organisation_id}

      assert {:ok, updated} = Customers.mark_kyc_verified(customer, scope)
      assert updated.kyc_status == "verified"
      assert updated.kyc_verified_by_id == admin.id
      refute is_nil(updated.kyc_verified_at)
    end

    test "mark_kyc_rejected/3 records the reason" do
      customer = customer_fixture()
      scope = %Scope{user: admin_fixture(), organisation_id: customer.organisation_id}

      assert {:ok, updated} = Customers.mark_kyc_rejected(customer, scope, "Blurry NRC photo")
      assert updated.kyc_status == "rejected"
      assert updated.kyc_rejection_reason == "Blurry NRC photo"
    end

    test "update_customer/2 cannot change kyc_status — it isn't in the generic changeset's cast list" do
      customer = customer_fixture()
      assert {:ok, updated} = Customers.update_customer(customer, %{kyc_status: "verified"})
      assert updated.kyc_status == "not_started"
    end
  end
end
