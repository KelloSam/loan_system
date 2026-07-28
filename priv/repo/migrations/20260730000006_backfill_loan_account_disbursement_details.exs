defmodule MiwayCreditCore.Repo.Migrations.BackfillLoanAccountDisbursementDetails do
  @moduledoc """
  Same reference format Applications.disburse_application/3 generates
  for new accounts (LN-<year>-<first 8 hex chars of the account's own
  id>) — existing accounts predate this field, so this backfills it
  from data already on the row rather than inventing a new one.
  disbursement_method is honestly "other" — the real channel these
  historical demo accounts were disbursed through was never recorded.
  """

  use Ecto.Migration

  def up do
    execute("""
    UPDATE loan_accounts
    SET contract_reference = 'LN-' || EXTRACT(YEAR FROM opened_at)::text || '-' || UPPER(LEFT(REPLACE(id::text, '-', ''), 8)),
        disbursement_method = 'other'
    WHERE contract_reference IS NULL
    """)
  end

  def down do
    :ok
  end
end
