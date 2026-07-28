defmodule MiwayCreditCore.Repo.Migrations.BackfillDisbursedStatus do
  @moduledoc """
  Under the old flat lifecycle, "approved" always meant a LoanAccount
  had already been created atomically — there was no in-between state.
  Under Step 9's split lifecycle that's what "disbursed" means now, so
  every existing approved application is relabeled disbursed here,
  with disbursed_at/disbursed_by_id backfilled from the existing
  decided_at/decided_by_id (the app never distinguished the two
  moments before this, so that's the closest available truth).
  Existing pending/rejected rows are untouched.
  """

  use Ecto.Migration

  def up do
    execute("""
    UPDATE loan_applications
    SET status = 'disbursed',
        disbursed_at = decided_at,
        disbursed_by_id = decided_by_id
    WHERE status = 'approved'
    """)
  end

  def down do
    execute("""
    UPDATE loan_applications
    SET status = 'approved',
        disbursed_at = NULL,
        disbursed_by_id = NULL
    WHERE status = 'disbursed'
    """)
  end
end
