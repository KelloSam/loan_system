defmodule MiwayCreditCore.CustomersTest do
  use MiwayCreditCore.DataCase, async: true

  import MiwayCreditCore.CustomersFixtures
  alias MiwayCreditCore.Customers
  alias MiwayCreditCore.Customers.Customer

  describe "create_customer/1" do
    test "creates a customer with valid attrs" do
      attrs = valid_customer_attrs(%{name: "Jane Banda"})
      assert {:ok, %Customer{} = customer} = Customers.create_customer(attrs)
      assert customer.name == "Jane Banda"
      assert customer.active
      assert customer.total_loans == 0
      assert Decimal.equal?(customer.current_balance, Decimal.new("0.00"))
    end

    test "requires name, phone, id_number" do
      assert {:error, changeset} = Customers.create_customer(%{})
      errors = errors_on(changeset)
      assert errors.name
      assert errors.phone
      assert errors.id_number
    end

    test "rejects a phone number not starting with 26/260" do
      attrs = valid_customer_attrs(%{phone: "0977123456"})
      assert {:error, changeset} = Customers.create_customer(attrs)
      assert errors_on(changeset).phone
    end

    test "rejects a too-short phone number" do
      attrs = valid_customer_attrs(%{phone: "260123"})
      assert {:error, changeset} = Customers.create_customer(attrs)
      assert errors_on(changeset).phone
    end

    test "rejects a non-numeric phone number" do
      attrs = valid_customer_attrs(%{phone: "260abc1234"})
      assert {:error, changeset} = Customers.create_customer(attrs)
      assert errors_on(changeset).phone
    end

    test "accepts a phone starting with 26 (not just 260)" do
      attrs = valid_customer_attrs(%{phone: "26977123456"})
      assert {:ok, _} = Customers.create_customer(attrs)
    end

    test "rejects a malformed email when provided" do
      attrs = valid_customer_attrs(%{email: "not-an-email"})
      assert {:error, changeset} = Customers.create_customer(attrs)
      assert errors_on(changeset).email
    end

    test "enforces unique phone" do
      attrs = valid_customer_attrs()
      assert {:ok, _} = Customers.create_customer(attrs)
      dup = valid_customer_attrs(%{phone: attrs.phone})
      assert {:error, changeset} = Customers.create_customer(dup)
      assert "has already been taken" in errors_on(changeset).phone
    end

    test "enforces unique id_number" do
      attrs = valid_customer_attrs()
      assert {:ok, _} = Customers.create_customer(attrs)
      dup = valid_customer_attrs(%{id_number: attrs.id_number})
      assert {:error, changeset} = Customers.create_customer(dup)
      assert "has already been taken" in errors_on(changeset).id_number
    end
  end

  describe "get_customer!/1, get_customer_by_*/1" do
    test "fetches by id, phone, email, id_number" do
      customer = customer_fixture(%{email: "lookup@example.com"})

      assert Customers.get_customer!(customer.id).id == customer.id
      assert Customers.get_customer_by_phone(customer.phone).id == customer.id
      assert Customers.get_customer_by_id_number(customer.id_number).id == customer.id
      assert Customers.get_customer_by_email("lookup@example.com").id == customer.id
    end

    test "get_customer!/1 raises for an unknown id" do
      assert_raise Ecto.NoResultsError, fn ->
        Customers.get_customer!(Ecto.UUID.generate())
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
      assert {:ok, _} = Customers.delete_customer(customer)
      assert_raise Ecto.NoResultsError, fn -> Customers.get_customer!(customer.id) end
    end
  end

  describe "list_customers/1 and count_customers/0" do
    test "lists customers ordered by name, paginated" do
      customer_fixture(%{name: "Charlie"})
      customer_fixture(%{name: "Alice"})
      customer_fixture(%{name: "Bob"})

      names = Customers.list_customers() |> Enum.map(& &1.name)
      assert names == Enum.sort(names)

      [first] = Customers.list_customers(per_page: 1)
      assert first.name == "Alice"
    end

    test "count_customers/0 reflects the number of customers" do
      before = Customers.count_customers()
      customer_fixture()
      customer_fixture()
      assert Customers.count_customers() == before + 2
    end
  end
end
