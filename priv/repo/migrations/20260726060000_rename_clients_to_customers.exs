defmodule MiwayCreditCore.Repo.Migrations.RenameClientsToCustomers do
  @moduledoc """
  Part of the Step 3 context restructure: `Clients` becomes `Customers`
  throughout. This only renames the table, its indexes/constraints, and
  the client_id foreign-key columns that reference it — no rows are
  dropped or recreated, so every existing customer, application, and
  account keeps its id and history intact.
  """

  use Ecto.Migration

  def up do
    rename table(:clients), to: table(:customers)
    execute "ALTER INDEX clients_pkey RENAME TO customers_pkey"
    execute "ALTER INDEX clients_id_number_index RENAME TO customers_id_number_index"
    execute "ALTER INDEX clients_phone_index RENAME TO customers_phone_index"
    execute "ALTER INDEX clients_email_index RENAME TO customers_email_index"

    rename table(:loan_applications), :client_id, to: :customer_id
    execute "ALTER TABLE loan_applications RENAME CONSTRAINT loan_applications_client_id_fkey TO loan_applications_customer_id_fkey"
    execute "ALTER INDEX loan_applications_client_id_index RENAME TO loan_applications_customer_id_index"

    rename table(:loan_accounts), :client_id, to: :customer_id
    execute "ALTER TABLE loan_accounts RENAME CONSTRAINT loan_accounts_client_id_fkey TO loan_accounts_customer_id_fkey"
    execute "ALTER INDEX loan_accounts_client_id_index RENAME TO loan_accounts_customer_id_index"
  end

  def down do
    execute "ALTER TABLE loan_accounts RENAME CONSTRAINT loan_accounts_customer_id_fkey TO loan_accounts_client_id_fkey"
    execute "ALTER INDEX loan_accounts_customer_id_index RENAME TO loan_accounts_client_id_index"
    rename table(:loan_accounts), :customer_id, to: :client_id

    execute "ALTER TABLE loan_applications RENAME CONSTRAINT loan_applications_customer_id_fkey TO loan_applications_client_id_fkey"
    execute "ALTER INDEX loan_applications_customer_id_index RENAME TO loan_applications_client_id_index"
    rename table(:loan_applications), :customer_id, to: :client_id

    execute "ALTER INDEX customers_email_index RENAME TO clients_email_index"
    execute "ALTER INDEX customers_phone_index RENAME TO clients_phone_index"
    execute "ALTER INDEX customers_id_number_index RENAME TO clients_id_number_index"
    execute "ALTER INDEX customers_pkey RENAME TO clients_pkey"
    rename table(:customers), to: table(:clients)
  end
end
