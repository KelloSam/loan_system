defmodule MiwayCreditCore.Repo.Migrations.AddLoanProductIdToApplicationsAndAccounts do
  @moduledoc """
  Additive pass, nullable here so existing rows keep working — the
  follow-up backfill migration seeds a default product per
  organisation and points every existing row at it, then a final
  migration makes these required.
  """

  use Ecto.Migration

  def change do
    alter table(:loan_applications) do
      add :loan_product_id, references(:products, type: :binary_id)
    end

    alter table(:loan_accounts) do
      add :loan_product_id, references(:products, type: :binary_id)
      add :interest_method, :string
    end

    create index(:loan_applications, [:loan_product_id])
    create index(:loan_accounts, [:loan_product_id])
  end
end
