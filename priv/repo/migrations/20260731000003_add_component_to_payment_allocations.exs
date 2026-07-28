defmodule MiwayCreditCore.Repo.Migrations.AddComponentToPaymentAllocations do
  @moduledoc """
  Step 13: which bucket (penalty/interest/principal) this allocation
  paid down — the traceable record of the new configurable allocation
  order (see Payments.record_payment/2).

  Existing allocations predate the penalty/interest/principal split
  (they were undifferentiated repayment), so they're backfilled as
  "principal" — the closest honest label, since no penalty existed
  yet and the interest/principal split wasn't tracked per-allocation
  before this migration either.
  """

  use Ecto.Migration

  def up do
    alter table(:payment_allocations) do
      add :component, :string
    end

    execute("UPDATE payment_allocations SET component = 'principal'")

    alter table(:payment_allocations) do
      modify :component, :string, null: false
    end
  end

  def down do
    alter table(:payment_allocations) do
      remove :component
    end
  end
end
