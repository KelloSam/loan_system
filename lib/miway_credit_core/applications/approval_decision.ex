defmodule MiwayCreditCore.Applications.ApprovalDecision do
  @moduledoc """
  One person's decision at one level of an application's approval
  workflow. A one-level, single-approver product produces exactly one
  of these per application (mirroring what used to be the bare
  decided_at/decided_by_id fields on LoanApplication itself); a
  two-level or committee product produces several — see
  `MiwayCreditCore.Applications.approve_application/3` for how they're
  aggregated into the application's actual status.

  Never edited or deleted — an append-only decision trail, same
  posture as `AccountingEntry`/`AuditLogs`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @decisions ~w(approved rejected conditional referred)
  @decline_reason_categories ~w(insufficient_income poor_credit_history incomplete_documentation policy_violation fraud_suspected other)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "approval_decisions" do
    field :level, :integer
    field :decision, :string
    field :notes, :string
    field :decline_reason_category, :string
    field :conditions, :string
    field :decided_at, :utc_datetime

    belongs_to :organisation, MiwayCreditCore.Organisations.Organisation, type: :binary_id
    belongs_to :loan_application, MiwayCreditCore.Applications.LoanApplication, type: :binary_id
    belongs_to :decided_by, MiwayCreditCore.Accounts.User

    timestamps(updated_at: false)
  end

  def changeset(approval_decision, attrs) do
    approval_decision
    |> cast(attrs, [
      :organisation_id,
      :loan_application_id,
      :decided_by_id,
      :level,
      :decision,
      :notes,
      :decline_reason_category,
      :conditions,
      :decided_at
    ])
    |> validate_required([
      :organisation_id,
      :loan_application_id,
      :decided_by_id,
      :level,
      :decision,
      :decided_at
    ])
    |> validate_inclusion(:decision, @decisions)
    |> validate_number(:level, greater_than: 0)
    |> validate_decline_reason_category()
    |> validate_conditions()
    |> validate_referral_notes()
    |> foreign_key_constraint(:organisation_id)
    |> foreign_key_constraint(:loan_application_id)
    |> foreign_key_constraint(:decided_by_id)
  end

  defp validate_decline_reason_category(changeset) do
    if get_field(changeset, :decision) == "rejected" do
      changeset
      |> validate_required([:decline_reason_category])
      |> validate_inclusion(:decline_reason_category, @decline_reason_categories)
    else
      changeset
    end
  end

  defp validate_conditions(changeset) do
    if get_field(changeset, :decision) == "conditional" do
      validate_required(changeset, [:conditions])
    else
      changeset
    end
  end

  defp validate_referral_notes(changeset) do
    if get_field(changeset, :decision) == "referred" do
      validate_required(changeset, [:notes])
    else
      changeset
    end
  end
end
