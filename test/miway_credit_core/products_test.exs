defmodule MiwayCreditCore.ProductsTest do
  use MiwayCreditCore.DataCase, async: true

  import MiwayCreditCore.OrganisationsFixtures

  alias MiwayCreditCore.Products
  alias MiwayCreditCore.Accounts.Scope

  describe "create_product/2" do
    test "creates a product under the caller's organisation, ignoring any organisation_id in attrs" do
      organisation = organisation_fixture()
      other = organisation_fixture()
      scope = %Scope{organisation_id: organisation.id}

      assert {:ok, product} =
               Products.create_product(
                 scope,
                 valid_product_attrs(%{"organisation_id" => other.id})
               )

      assert product.organisation_id == organisation.id
    end

    test "requires a concrete organisation scope, not :all" do
      assert_raise ArgumentError, fn ->
        Products.create_product(%Scope{organisation_id: :all}, valid_product_attrs())
      end
    end

    test "rejects a maximum_principal below minimum_principal" do
      organisation = organisation_fixture()
      scope = %Scope{organisation_id: organisation.id}

      attrs = valid_product_attrs(%{"minimum_principal" => "5000", "maximum_principal" => "1000"})
      assert {:error, changeset} = Products.create_product(scope, attrs)

      assert "must be greater than or equal to minimum_principal" in errors_on(changeset).maximum_principal
    end

    test "rejects a maximum_term_months below minimum_term_months" do
      organisation = organisation_fixture()
      scope = %Scope{organisation_id: organisation.id}

      attrs = valid_product_attrs(%{"minimum_term_months" => "12", "maximum_term_months" => "6"})
      assert {:error, changeset} = Products.create_product(scope, attrs)

      assert "must be greater than or equal to minimum_term_months" in errors_on(changeset).maximum_term_months
    end

    test "rejects effective_until before effective_from" do
      organisation = organisation_fixture()
      scope = %Scope{organisation_id: organisation.id}

      attrs =
        valid_product_attrs(%{
          "effective_from" => "2026-06-01",
          "effective_until" => "2026-01-01"
        })

      assert {:error, changeset} = Products.create_product(scope, attrs)
      assert "must be on or after effective_from" in errors_on(changeset).effective_until
    end

    test "rejects a duplicate name within the same organisation" do
      organisation = organisation_fixture()
      scope = %Scope{organisation_id: organisation.id}
      {:ok, _} = Products.create_product(scope, valid_product_attrs(%{"name" => "Business Loan"}))

      assert {:error, changeset} =
               Products.create_product(scope, valid_product_attrs(%{"name" => "Business Loan"}))

      assert "has already been taken" in errors_on(changeset).organisation_id
    end

    test "the same name is allowed across different organisations" do
      organisation = organisation_fixture()
      other = organisation_fixture()

      {:ok, _} =
        Products.create_product(
          %Scope{organisation_id: organisation.id},
          valid_product_attrs(%{"name" => "Shared Name"})
        )

      assert {:ok, _} =
               Products.create_product(
                 %Scope{organisation_id: other.id},
                 valid_product_attrs(%{"name" => "Shared Name"})
               )
    end
  end

  describe "list_products/1 and list_available_products/1" do
    test "list_products includes retired products; list_available_products excludes them" do
      organisation = organisation_fixture()
      scope = %Scope{organisation_id: organisation.id}

      {:ok, product} =
        Products.create_product(scope, valid_product_attrs(%{"name" => "Retiring Soon"}))

      {:ok, product} = Products.retire_product(product)

      assert Enum.any?(Products.list_products(scope), &(&1.id == product.id))
      refute Enum.any?(Products.list_available_products(scope), &(&1.id == product.id))
    end

    test "list_available_products excludes a product whose effective window hasn't started or has ended" do
      organisation = organisation_fixture()
      scope = %Scope{organisation_id: organisation.id}

      {:ok, future} =
        Products.create_product(
          scope,
          valid_product_attrs(%{
            "name" => "Future",
            "effective_from" => Date.add(Date.utc_today(), 30)
          })
        )

      {:ok, expired} =
        Products.create_product(
          scope,
          valid_product_attrs(%{
            "name" => "Expired",
            "effective_from" => Date.add(Date.utc_today(), -60),
            "effective_until" => Date.add(Date.utc_today(), -1)
          })
        )

      available_ids = scope |> Products.list_available_products() |> Enum.map(& &1.id)
      refute future.id in available_ids
      refute expired.id in available_ids
    end

    test "a product in another organisation never appears, even with the same scope's org filtered out" do
      organisation = organisation_fixture()
      other = organisation_fixture()

      {:ok, other_product} =
        Products.create_product(%Scope{organisation_id: other.id}, valid_product_attrs())

      scope = %Scope{organisation_id: organisation.id}
      refute Enum.any?(Products.list_products(scope), &(&1.id == other_product.id))
    end

    test "scope :all sees products across every organisation" do
      organisation = organisation_fixture()
      other = organisation_fixture()

      {:ok, p1} =
        Products.create_product(%Scope{organisation_id: organisation.id}, valid_product_attrs())

      {:ok, p2} =
        Products.create_product(%Scope{organisation_id: other.id}, valid_product_attrs())

      ids = %Scope{organisation_id: :all} |> Products.list_products() |> Enum.map(& &1.id)
      assert p1.id in ids
      assert p2.id in ids
    end
  end

  test "get_product!/2 raises for a product outside the scope's organisation" do
    organisation = organisation_fixture()
    other = organisation_fixture()

    {:ok, product} =
      Products.create_product(%Scope{organisation_id: other.id}, valid_product_attrs())

    assert_raise Ecto.NoResultsError, fn ->
      Products.get_product!(%Scope{organisation_id: organisation.id}, product.id)
    end
  end

  describe "update_product/2" do
    test "updates terms in place" do
      organisation = organisation_fixture()

      {:ok, product} =
        Products.create_product(%Scope{organisation_id: organisation.id}, valid_product_attrs())

      assert {:ok, updated} = Products.update_product(product, %{"interest_rate" => "22.50"})
      assert Decimal.equal?(updated.interest_rate, Decimal.new("22.50"))
    end
  end

  describe "retire_product/1 and activate_product/1" do
    test "retire_product sets status to retired; activate_product reverses it" do
      organisation = organisation_fixture()

      {:ok, product} =
        Products.create_product(%Scope{organisation_id: organisation.id}, valid_product_attrs())

      assert {:ok, retired} = Products.retire_product(product)
      assert retired.status == "retired"

      assert {:ok, reactivated} = Products.activate_product(retired)
      assert reactivated.status == "active"
    end
  end

  defp valid_product_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      "name" => "Test Product #{System.unique_integer([:positive])}",
      "minimum_principal" => "100.00",
      "maximum_principal" => "50000.00",
      "interest_method" => "reducing_balance",
      "interest_rate" => "18.00",
      "minimum_term_months" => "1",
      "maximum_term_months" => "24",
      "repayment_frequency" => "monthly",
      "effective_from" => Date.utc_today()
    })
  end
end
