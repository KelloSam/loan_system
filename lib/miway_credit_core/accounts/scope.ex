defmodule MiwayCreditCore.Accounts.Scope do
  @moduledoc """
  Who is asking, and which organisation they're allowed to see. Built
  once per request in AuthPlug and threaded as the first argument
  into every context function that touches organisation-owned data.

  `organisation_id` is either a binary_id (staff scoped to exactly one
  organisation via OrganisationMembership, or a customer's own
  Customer.organisation_id) or the atom `:all` — the one deliberate
  escape hatch from tenant isolation, granted only to
  platform_administrator, whose whole point is seeing every
  organisation.
  """

  defstruct [:user, :staff_member, :customer, :organisation_id]

  alias MiwayCreditCore.Accounts.{User, StaffMember}
  alias MiwayCreditCore.Customers.Customer

  def for_platform_administrator(%User{} = user, %StaffMember{} = staff_member) do
    %__MODULE__{user: user, staff_member: staff_member, organisation_id: :all}
  end

  def for_staff_member(%User{} = user, %StaffMember{} = staff_member, organisation_id)
      when is_binary(organisation_id) do
    %__MODULE__{user: user, staff_member: staff_member, organisation_id: organisation_id}
  end

  def for_customer(%User{} = user, %Customer{} = customer) do
    %__MODULE__{user: user, customer: customer, organisation_id: customer.organisation_id}
  end
end
