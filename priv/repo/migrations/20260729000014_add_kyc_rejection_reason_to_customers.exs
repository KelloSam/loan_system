defmodule MiwayCreditCore.Repo.Migrations.AddKycRejectionReasonToCustomers do
  @moduledoc """
  Missed in the initial KYC-fields pass: `mark_kyc_rejected/3` needs
  somewhere to persist why, the same way `LoanApplication.rejection_reason`
  already does for application rejections.
  """

  use Ecto.Migration

  def change do
    alter table(:customers) do
      add :kyc_rejection_reason, :string
    end
  end
end
