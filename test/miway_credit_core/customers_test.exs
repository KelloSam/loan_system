defmodule MiwayCreditCore.CustomersTest do
  use MiwayCreditCore.DataCase, async: true

  import MiwayCreditCore.CustomersFixtures
  import MiwayCreditCore.OrganisationsFixtures
  alias MiwayCreditCore.Customers
  alias MiwayCreditCore.Customers.Customer
  alias MiwayCreditCore.Accounts.Scope

  describe "create_customer/2" do
    test "creates a customer with valid attrs" do
      organisation = organisation_fixture()
      scope = %Scope{organisation_id: organisation.id}
      attrs = valid_customer_attrs(%{name: "Jane Banda"})

      assert {:ok, %Customer{} = customer} = Customers.create_customer(scope, attrs)
      assert customer.name == "Jane Banda"
      assert customer.organisation_id == organisation.id
      assert customer.active
      assert customer.total_loans == 0
      assert Decimal.equal?(customer.current_balance, Decimal.new("0.00"))
    end

    test "requires name, phone, id_number" do
      scope = %Scope{organisation_id: organisation_fixture().id}
      assert {:error, changeset} = Customers.create_customer(scope, %{})
      errors = errors_on(changeset)
      assert errors.name
      assert errors.phone
      assert errors.id_number
    end

    test "rejects a phone number not starting with 26/260" do
      scope = %Scope{organisation_id: organisation_fixture().id}
      attrs = valid_customer_attrs(%{phone: "0977123456"})
      assert {:error, changeset} = Customers.create_customer(scope, attrs)
      assert errors_on(changeset).phone
    end

    test "rejects a too-short phone number" do
      scope = %Scope{organisation_id: organisation_fixture().id}
      attrs = valid_customer_attrs(%{phone: "260123"})
      assert {:error, changeset} = Customers.create_customer(scope, attrs)
      assert errors_on(changeset).phone
    end

    test "rejects a non-numeric phone number" do
      scope = %Scope{organisation_id: organisation_fixture().id}
      attrs = valid_customer_attrs(%{phone: "260abc1234"})
      assert {:error, changeset} = Customers.create_customer(scope, attrs)
      assert errors_on(changeset).phone
    end

    test "accepts a phone starting with 26 (not just 260)" do
      scope = %Scope{organisation_id: organisation_fixture().id}
      attrs = valid_customer_attrs(%{phone: "26977123456"})
      assert {:ok, _} = Customers.create_customer(scope, attrs)
    end

    test "rejects a malformed email when provided" do
      scope = %Scope{organisation_id: organisation_fixture().id}
      attrs = valid_customer_attrs(%{email: "not-an-email"})
      assert {:error, changeset} = Customers.create_customer(scope, attrs)
      assert errors_on(changeset).email
    end

    test "enforces unique phone" do
      scope = %Scope{organisation_id: organisation_fixture().id}
      attrs = valid_customer_attrs()
      assert {:ok, _} = Customers.create_customer(scope, attrs)
      dup = valid_customer_attrs(%{phone: attrs.phone})
      assert {:error, changeset} = Customers.create_customer(scope, dup)
      assert "has already been taken" in errors_on(changeset).phone
    end

    test "enforces unique id_number" do
      scope = %Scope{organisation_id: organisation_fixture().id}
      attrs = valid_customer_attrs()
      assert {:ok, _} = Customers.create_customer(scope, attrs)
      dup = valid_customer_attrs(%{id_number: attrs.id_number})
      assert {:error, changeset} = Customers.create_customer(scope, dup)
      assert "has already been taken" in errors_on(changeset).id_number
    end

    test "raises when scope is :all — creation always requires a concrete organisation" do
      assert_raise ArgumentError, fn ->
        Customers.create_customer(%Scope{organisation_id: :all}, valid_customer_attrs())
      end
    end
  end

  describe "get_customer!/2, get_customer_by_*/1" do
    test "fetches by id, phone, email, id_number" do
      customer = customer_fixture(%{email: "lookup@example.com"})
      scope = %Scope{organisation_id: customer.organisation_id}

      assert Customers.get_customer!(scope, customer.id).id == customer.id
      assert Customers.get_customer_by_phone(customer.phone).id == customer.id
      assert Customers.get_customer_by_id_number(customer.id_number).id == customer.id
      assert Customers.get_customer_by_email("lookup@example.com").id == customer.id
    end

    test "get_customer!/2 raises for an unknown id" do
      scope = %Scope{organisation_id: organisation_fixture().id}
      assert_raise Ecto.NoResultsError, fn ->
        Customers.get_customer!(scope, Ecto.UUID.generate())
      end
    end

    test "get_customer_by_phone/1 returns nil when not found" do
      assert Customers.get_customer_by_phone("260000000000") == nil
    end
  end

  describe "update_customer/2" do
    test "updates allowed fields" do
      customer = customer_fixture()
      assert {:ok, updated} = Customers.update_customer(customer, %{name: "Renamed", address: "Lusaka"})
      assert updated.name == "Renamed"
      assert updated.address == "Lusaka"
    end

    test "re-validates phone format on update" do
      customer = customer_fixture()
      assert {:error, changeset} = Customers.update_customer(customer, %{phone: "invalid"})
      assert errors_on(changeset).phone
    end
  end

  describe "delete_customer/1" do
    test "removes the customer" do
      customer = customer_fixture()
      scope = %Scope{organisation_id: customer.organisation_id}
      assert {:ok, _} = Customers.delete_customer(customer)
      assert_raise Ecto.NoResultsError, fn -> Customers.get_customer!(scope, customer.id) end
    end
  end

  describe "list_customers/2 and count_customers/1" do
    test "lists customers ordered by name, paginated, scoped to one organisation" do
      organisation = organisation_fixture()
      scope = %Scope{organisation_id: organisation.id}
      customer_fixture_in_organisation(organisation, %{name: "Charlie"})
      customer_fixture_in_organisation(organisation, %{name: "Alice"})
      customer_fixture_in_organisation(organisation, %{name: "Bob"})

      names = Customers.list_customers(scope) |> Enum.map(& &1.name)
      assert names == Enum.sort(names)

      [first] = Customers.list_customers(scope, per_page: 1)
      assert first.name == "Alice"
    end

    test "count_customers/1 reflects the number of customers in one organisation" do
      organisation = organisation_fixture()
      scope = %Scope{organisation_id: organisation.id}
      assert Customers.count_customers(scope) == 0

      customer_fixture_in_organisation(organisation)
      customer_fixture_in_organisation(organisation)
      assert Customers.count_customers(scope) == 2
    end

    test "never counts or lists another organisation's customers" do
      organisation = organisation_fixture()
      scope = %Scope{organisation_id: organisation.id}
      customer_fixture_in_organisation(organisation)

      other_customer = customer_fixture()

      assert Customers.count_customers(scope) == 1
      refute other_customer.id in Enum.map(Customers.list_customers(scope), & &1.id)
    end
  end
end
