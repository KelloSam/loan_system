defmodule MiwayCreditCore.Repo.Migrations.AddIdempotencyKeyToPaymentTransactions do
  @moduledoc """
  Guards against a double-click or network retry on the "Record
  Payment" form creating two separate transactions for the same
  submission. Nullable — existing rows and any non-form caller are
  unaffected; Postgres treats NULL as distinct from every other NULL
  in a unique index, so the constraint only bites when two rows
  actually share the same (loan_account_id, idempotency_key) pair.
  """

  use Ecto.Migration

  def change do
    alter table(:payment_transactions) do
      add :idempotency_key, :string
    end

    create unique_index(:payment_transactions, [:loan_account_id, :idempotency_key])
  end
end
