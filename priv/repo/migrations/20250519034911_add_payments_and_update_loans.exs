defmodule MiwayCreditCore.Repo.Migrations.AddPaymentsAndUpdateLoans do
  use Ecto.Migration

  def change do
    # Add purpose field to existing loans table
    alter table(:loans) do
      add :purpose, :string
    end

    # Add new fields to existing payments table
    alter table(:payments) do
      add :due_date, :date
    end
  end
end
