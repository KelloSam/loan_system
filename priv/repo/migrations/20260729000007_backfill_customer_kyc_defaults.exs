defmodule MiwayCreditCore.Repo.Migrations.BackfillCustomerKycDefaults do
  @moduledoc """
  Existing customers predate the individual/business distinction. All
  of today's dev/demo data is, in practice, individuals identified by
  NRC — "nrc" is a safe, honest default, not a guess about real
  identity documents nobody has actually verified yet (that's exactly
  what `kyc_status: "not_started"` communicates).
  """

  use Ecto.Migration

  def up do
    execute("""
    UPDATE customers
    SET customer_type = 'individual',
        id_type = 'nrc',
        address_line = address,
        kyc_status = 'not_started'
    """)
  end

  def down do
    :ok
  end
end
