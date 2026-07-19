defmodule LoanSystem.ClientsTest do
  use LoanSystem.DataCase, async: true

  import LoanSystem.ClientsFixtures
  alias LoanSystem.Clients
  alias LoanSystem.Clients.Client

  describe "create_client/1" do
    test "creates a client with valid attrs" do
      attrs = valid_client_attrs(%{name: "Jane Banda"})
      assert {:ok, %Client{} = client} = Clients.create_client(attrs)
      assert client.name == "Jane Banda"
      assert client.active
      assert client.total_loans == 0
      assert Decimal.equal?(client.current_balance, Decimal.new("0.00"))
    end

    test "requires name, phone, id_number" do
      assert {:error, changeset} = Clients.create_client(%{})
      errors = errors_on(changeset)
      assert errors.name
      assert errors.phone
      assert errors.id_number
    end

    test "rejects a phone number not starting with 26/260" do
      attrs = valid_client_attrs(%{phone: "0977123456"})
      assert {:error, changeset} = Clients.create_client(attrs)
      assert errors_on(changeset).phone
    end

    test "rejects a too-short phone number" do
      attrs = valid_client_attrs(%{phone: "260123"})
      assert {:error, changeset} = Clients.create_client(attrs)
      assert errors_on(changeset).phone
    end

    test "rejects a non-numeric phone number" do
      attrs = valid_client_attrs(%{phone: "260abc1234"})
      assert {:error, changeset} = Clients.create_client(attrs)
      assert errors_on(changeset).phone
    end

    test "accepts a phone starting with 26 (not just 260)" do
      attrs = valid_client_attrs(%{phone: "26977123456"})
      assert {:ok, _} = Clients.create_client(attrs)
    end

    test "rejects a malformed email when provided" do
      attrs = valid_client_attrs(%{email: "not-an-email"})
      assert {:error, changeset} = Clients.create_client(attrs)
      assert errors_on(changeset).email
    end

    test "enforces unique phone" do
      attrs = valid_client_attrs()
      assert {:ok, _} = Clients.create_client(attrs)
      dup = valid_client_attrs(%{phone: attrs.phone})
      assert {:error, changeset} = Clients.create_client(dup)
      assert "has already been taken" in errors_on(changeset).phone
    end

    test "enforces unique id_number" do
      attrs = valid_client_attrs()
      assert {:ok, _} = Clients.create_client(attrs)
      dup = valid_client_attrs(%{id_number: attrs.id_number})
      assert {:error, changeset} = Clients.create_client(dup)
      assert "has already been taken" in errors_on(changeset).id_number
    end
  end

  describe "get_client!/1, get_client_by_*/1" do
    test "fetches by id, phone, email, id_number" do
      client = client_fixture(%{email: "lookup@example.com"})

      assert Clients.get_client!(client.id).id == client.id
      assert Clients.get_client_by_phone(client.phone).id == client.id
      assert Clients.get_client_by_id_number(client.id_number).id == client.id
      assert Clients.get_client_by_email("lookup@example.com").id == client.id
    end

    test "get_client!/1 raises for an unknown id" do
      assert_raise Ecto.NoResultsError, fn ->
        Clients.get_client!(Ecto.UUID.generate())
      end
    end

    test "get_client_by_phone/1 returns nil when not found" do
      assert Clients.get_client_by_phone("260000000000") == nil
    end
  end

  describe "update_client/2" do
    test "updates allowed fields" do
      client = client_fixture()
      assert {:ok, updated} = Clients.update_client(client, %{name: "Renamed", address: "Lusaka"})
      assert updated.name == "Renamed"
      assert updated.address == "Lusaka"
    end

    test "re-validates phone format on update" do
      client = client_fixture()
      assert {:error, changeset} = Clients.update_client(client, %{phone: "invalid"})
      assert errors_on(changeset).phone
    end
  end

  describe "delete_client/1" do
    test "removes the client" do
      client = client_fixture()
      assert {:ok, _} = Clients.delete_client(client)
      assert_raise Ecto.NoResultsError, fn -> Clients.get_client!(client.id) end
    end
  end

  describe "list_clients/1 and count_clients/0" do
    test "lists clients ordered by name, paginated" do
      client_fixture(%{name: "Charlie"})
      client_fixture(%{name: "Alice"})
      client_fixture(%{name: "Bob"})

      names = Clients.list_clients() |> Enum.map(& &1.name)
      assert names == Enum.sort(names)

      [first] = Clients.list_clients(per_page: 1)
      assert first.name == "Alice"
    end

    test "count_clients/0 reflects the number of clients" do
      before = Clients.count_clients()
      client_fixture()
      client_fixture()
      assert Clients.count_clients() == before + 2
    end
  end
end
