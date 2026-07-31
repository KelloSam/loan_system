defmodule MiwayCreditCore.AccountsFixtures do
  @moduledoc "Test helpers for creating MiwayCreditCore.Accounts entities."

  def valid_user_email, do: "user#{System.unique_integer([:positive])}@example.com"
  def valid_user_password, do: "SuperSecret123"

  def valid_user_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: valid_user_email(),
      password: valid_user_password()
    })
  end

  @doc "A bare login with no StaffMember or CustomerUser attached — useful for testing the orphaned-account case."
  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attrs()
      |> MiwayCreditCore.Accounts.create_user()

    user
  end

  @doc """
  A login + StaffMember pair. Returns the User (role \\\\ "loan_officer").

  Every role except "platform_administrator" also gets an
  OrganisationMembership (with its matching RoleAssignment already
  granted) in a fresh, throwaway organisation — AuthPlug's scope
  resolution requires a membership for any staff member who isn't
  platform-wide, and Authorization.authorized?/2 requires a
  RoleAssignment for any permission check to pass. The vast majority
  of tests using this fixture don't care which organisation, just
  that one exists with real permissions attached.
  """
  def staff_member_fixture(role \\ "loan_officer", attrs \\ %{}) do
    {:ok, user, staff_member} =
      attrs
      |> valid_user_attrs()
      |> MiwayCreditCore.Accounts.register_staff_member(role)

    if role != "platform_administrator" do
      organisation = MiwayCreditCore.OrganisationsFixtures.organisation_fixture()

      {:ok, _membership} =
        MiwayCreditCore.Authorization.enroll_staff_member(staff_member, organisation.id)
    end

    user
  end

  @doc "Kept for existing test call sites that expect an admin-role User — a platform_administrator StaffMember."
  def admin_fixture(attrs \\ %{}), do: staff_member_fixture("platform_administrator", attrs)

  @doc "A login + CustomerUser pair, linked to the given Customer. Returns the User."
  def customer_user_fixture(%MiwayCreditCore.Customers.Customer{} = customer, attrs \\ %{}) do
    {:ok, user, _customer_user} =
      attrs
      |> valid_user_attrs()
      |> MiwayCreditCore.Accounts.register_customer_user(customer.id)

    user
  end
end
