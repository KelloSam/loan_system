defmodule MiwayCreditCore.Repo.Migrations.AddPayableAndFailureDetailsToPaymentTransactions do
  @moduledoc """
  Step 13: payable_amount/overpayment_amount split the transaction's
  amount into what actually applied to the balance vs. what was
  unapplied excess (an overpayment). failed_at/failed_by_id/fail_reason
  mirror the existing voided_* trio, for a posted payment that later
  fails (e.g. a bounced cheque) rather than being voided by mistake.

  Constant defaults (unlike Step 12's contract_reference, which needed
  a per-row computed backfill) — safe as one migration, no separate
  backfill step. payable_amount backfills to the existing amount for
  every prior row (no prior row had an overpayment, since overpayment
  was previously rejected outright).
  """

  use Ecto.Migration

  def up do
    alter table(:payment_transactions) do
      add :payable_amount, :decimal, default: 0.0
      add :overpayment_amount, :decimal, null: false, default: 0.0

      add :failed_at, :utc_datetime
      add :failed_by_id, references(:users)
      add :fail_reason, :string
    end

    execute("UPDATE payment_transactions SET payable_amount = amount")

    alter table(:payment_transactions) do
      modify :payable_amount, :decimal, null: false
    end
  end

  def down do
    alter table(:payment_transactions) do
      remove :payable_amount
      remove :overpayment_amount
      remove :failed_at
      remove :failed_by_id
      remove :fail_reason
    end
  end
end
