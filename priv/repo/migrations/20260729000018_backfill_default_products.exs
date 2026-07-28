defmodule MiwayCreditCore.Repo.Migrations.BackfillDefaultProducts do
  @moduledoc """
  Every organisation gets one "Standard Loan" product matching
  exactly today's hard-coded pre-Step-8 behavior (18.00% reducing
  balance, monthly, no fee/penalty/grace, no requirements, generous
  bounds) — so nothing about existing lending behavior changes for an
  organisation that never touches product configuration. Every
  existing loan_application/loan_account is pointed at its
  organisation's new default product.
  """

  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO products (
      id, organisation_id, name, description,
      minimum_principal, maximum_principal, interest_method, interest_rate,
      minimum_term_months, maximum_term_months, repayment_frequency,
      origination_fee_percent, late_payment_penalty_percent, grace_period_days,
      requires_collateral, requires_guarantor, minimum_guarantors, requires_crb_check,
      minimum_approval_role, status, effective_from, effective_until,
      inserted_at, updated_at
    )
    SELECT
      gen_random_uuid(), id, 'Standard Loan',
      'Default product seeded during the Step 8 migration, matching this organisation''s lending behavior before configurable products existed.',
      0.01, 999999999.99, 'reducing_balance', 18.00,
      1, 360, 'monthly',
      0.00, 0.00, 0,
      false, false, 0, false,
      NULL, 'active', CURRENT_DATE, NULL,
      now(), now()
    FROM organisations
    """)

    execute("""
    UPDATE loan_applications
    SET loan_product_id = products.id
    FROM products
    WHERE products.organisation_id = loan_applications.organisation_id
      AND products.name = 'Standard Loan'
    """)

    execute("""
    UPDATE loan_accounts
    SET loan_product_id = products.id,
        interest_method = 'reducing_balance'
    FROM products
    WHERE products.organisation_id = loan_accounts.organisation_id
      AND products.name = 'Standard Loan'
    """)
  end

  def down do
    :ok
  end
end
