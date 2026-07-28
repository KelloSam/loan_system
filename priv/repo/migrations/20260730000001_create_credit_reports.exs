defmodule MiwayCreditCore.Repo.Migrations.CreateCreditReports do
  @moduledoc """
  CreditReporting's first real schema — see
  lib/miway_credit_core/credit_reporting.ex for why Enquiries/Reports
  collapse into this one table for the manual-adapter case, and why
  Consents isn't duplicated here at all (reuses Customers.Consent's
  existing credit_check consent type).
  """

  use Ecto.Migration

  def change do
    create table(:credit_reports, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organisation_id, references(:organisations, type: :binary_id), null: false
      add :customer_id, references(:customers, type: :binary_id), null: false

      add :provider, :string, null: false, default: "manual"
      add :outcome, :string, null: false
      add :score, :integer
      add :reference_number, :string
      add :summary, :text
      add :checked_at, :date, null: false

      add :requested_by_id, references(:users), null: false

      # usec precision deliberately: get_latest_report_for_customer/2
      # breaks a same-day checked_at tie by inserted_at, and two
      # manual entries (e.g. a same-day correction) can easily land in
      # the same second otherwise.
      timestamps(type: :utc_datetime_usec)
    end

    create index(:credit_reports, [:organisation_id, :customer_id])
  end
end
