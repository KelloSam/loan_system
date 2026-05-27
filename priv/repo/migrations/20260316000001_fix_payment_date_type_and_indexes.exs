defmodule LoanSystem.Repo.Migrations.FixPaymentDateTypeAndIndexes do
  use Ecto.Migration

  def up do
    # Fix payment_date column type: was :utc_datetime in the original migration
    # but the Payment schema declares it as :date. Align the DB column with the schema.
    execute "ALTER TABLE payments ALTER COLUMN payment_date TYPE date USING payment_date::date"

    # Drop the now-redundant single-column payment_date index (covered by the composite below)
    drop_if_exists index(:payments, [:payment_date])

    # Add a composite index that matches the get_upcoming_payments/1 query pattern:
    #   WHERE loan_id = ? AND status = 'pending' AND payment_date >= ?
    # This index supersedes the separate [:loan_id] index for payment-scheduling queries.
    create index(:payments, [:loan_id, :status, :payment_date])
  end

  def down do
    drop_if_exists index(:payments, [:loan_id, :status, :payment_date])

    # Restore the original utc_datetime column and index
    execute "ALTER TABLE payments ALTER COLUMN payment_date TYPE timestamp without time zone USING payment_date::timestamp"
    create index(:payments, [:payment_date])
  end
end
