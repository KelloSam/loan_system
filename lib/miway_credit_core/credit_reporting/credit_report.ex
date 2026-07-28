defmodule MiwayCreditCore.CreditReporting.CreditReport do
  @moduledoc """
  The record of one credit reference bureau (CRB) check on a customer.

  Covers what a separate `Enquiries`/`Reports` split would otherwise
  need, collapsed into one schema because `ManualAdapter` is
  synchronous — staff check the bureau outside the system, then
  record what they found, all in one event. That split becomes real
  again once a `ProviderAdapter` needs to track a request separately
  from its (possibly async) result — see
  `docs/architecture/context_boundaries.md`.

  Never edited or revoked — a superseded report is simply not the
  latest one anymore (`CreditReporting.get_latest_report_for_customer/2`
  always reads the most recent by `checked_at`).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @providers ~w(manual)
  @outcomes ~w(clear adverse)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "credit_reports" do
    field :provider, :string, default: "manual"
    field :outcome, :string
    field :score, :integer
    field :reference_number, :string
    field :summary, :string
    field :checked_at, :date

    belongs_to :organisation, MiwayCreditCore.Organisations.Organisation, type: :binary_id
    belongs_to :customer, MiwayCreditCore.Customers.Customer, type: :binary_id
    belongs_to :requested_by, MiwayCreditCore.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(credit_report, attrs) do
    credit_report
    |> cast(attrs, [
      :organisation_id, :customer_id, :requested_by_id,
      :provider, :outcome, :score, :reference_number, :summary, :checked_at
    ])
    |> validate_required([:organisation_id, :customer_id, :requested_by_id, :provider, :outcome, :checked_at])
    |> validate_inclusion(:provider, @providers)
    |> validate_inclusion(:outcome, @outcomes)
    |> foreign_key_constraint(:organisation_id)
    |> foreign_key_constraint(:customer_id)
    |> foreign_key_constraint(:requested_by_id)
  end
end
