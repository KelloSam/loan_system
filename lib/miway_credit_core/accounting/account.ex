defmodule MiwayCreditCore.Accounting.Account do
  @moduledoc """
  One row of the chart of accounts (the general ledger's account
  list) — not to be confused with `MiwayCreditCore.Accounts.User` or
  `MiwayCreditCore.Lending.LoanAccount`. A small fixed seed per
  organisation (see `MiwayCreditCore.Accounting.GeneralLedger.seed_chart_of_accounts/1`),
  not user-editable in this pass.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @account_types ~w(asset liability equity income expense)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "accounts" do
    field :code, :string
    field :name, :string
    field :account_type, :string

    belongs_to :organisation, MiwayCreditCore.Organisations.Organisation, type: :binary_id

    timestamps()
  end

  def changeset(account, attrs) do
    account
    |> cast(attrs, [:organisation_id, :code, :name, :account_type])
    |> validate_required([:organisation_id, :code, :name, :account_type])
    |> validate_inclusion(:account_type, @account_types)
    |> foreign_key_constraint(:organisation_id)
    |> unique_constraint(:code, name: :accounts_organisation_id_code_index)
  end
end
