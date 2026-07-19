defmodule LoanSystem.Repo.Migrations.MakePaymentDateNullable do
  use Ecto.Migration

  @moduledoc """
  payment_date was NOT NULL at the DB level, but the changeset's own
  validation only requires *either* due_date or payment_date — so a
  scheduled-but-unpaid installment (due_date only) could never actually
  be inserted. Needed now that create_loan/1 generates a full repayment
  schedule of unpaid installments on approval (see Loans.generate_repayment_schedule/1).
  """

  def change do
    alter table(:payments) do
      modify :payment_date, :date, null: true
    end
  end
end
