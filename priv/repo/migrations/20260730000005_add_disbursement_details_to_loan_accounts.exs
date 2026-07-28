defmodule MiwayCreditCore.Repo.Migrations.AddDisbursementDetailsToLoanAccounts do
  @moduledoc """
  Step 12: a contract reference (system-generated, not user-entered —
  see LoanAccount.generate_contract_reference/1), the outbound mirror
  of PaymentTransaction's method/reference fields, and a "reversed"
  status + its own timestamp/actor/reason trio, same shape as the
  existing closed_at-style fields already on this table.

  Additive/nullable here — existing loan_accounts predate both fields
  and can't retroactively know their real disbursement channel; the
  follow-up backfill migration fills in a generated reference and an
  honest "other" method for them, then a final migration makes both
  required.
  """

  use Ecto.Migration

  def change do
    alter table(:loan_accounts) do
      add :contract_reference, :string
      add :disbursement_method, :string
      add :disbursement_reference, :string

      add :reversed_at, :utc_datetime
      add :reversed_by_id, references(:users)
      add :reversal_reason, :string
    end

    create unique_index(:loan_accounts, [:contract_reference])
  end
end
