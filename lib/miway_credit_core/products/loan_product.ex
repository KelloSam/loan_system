defmodule MiwayCreditCore.Products.LoanProduct do
  @moduledoc """
  A configurable set of lending terms — min/max principal, interest
  method/rate, permitted term, repayment frequency, fees, penalties,
  grace period, security/guarantor/CRB/affordability requirements,
  minimum approval role, and an effective-date window.

  Never versioned and never hard-deleted. A `LoanAccount` freezes the
  terms it was issued under directly onto itself at approval time
  (see `MiwayCreditCore.Applications.approve_application/2`) rather
  than holding a live reference back to this row — so editing a
  product here, or retiring it, never changes an existing loan's
  terms. `retire_product/1` (see the `Products` context) just stops a
  product from being selectable for *new* applications.

  Only `interest_method: "reducing_balance"` and
  `repayment_frequency: "monthly"` are accepted today — the only
  methods `InterestCalculator`/repayment-schedule generation actually
  implement. Other values are reserved names, not silently-broken
  implementations.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @interest_methods ~w(reducing_balance)
  @repayment_frequencies ~w(monthly)
  @approval_roles ~w(loan_officer organisation_administrator platform_administrator)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "products" do
    field :name, :string
    field :description, :string

    field :minimum_principal, :decimal
    field :maximum_principal, :decimal
    field :interest_method, :string
    field :interest_rate, :decimal
    field :minimum_term_months, :integer
    field :maximum_term_months, :integer
    field :repayment_frequency, :string

    field :origination_fee_percent, :decimal, default: Decimal.new("0.00")
    field :late_payment_penalty_percent, :decimal, default: Decimal.new("0.00")
    field :grace_period_days, :integer, default: 0

    field :requires_collateral, :boolean, default: false
    field :requires_guarantor, :boolean, default: false
    field :minimum_guarantors, :integer, default: 0
    field :requires_crb_check, :boolean, default: false
    field :requires_affordability_check, :boolean, default: false
    field :max_debt_to_income_percent, :decimal, default: Decimal.new("40.00")
    field :minimum_approval_role, :string

    field :status, :string, default: "active"
    field :effective_from, :date
    field :effective_until, :date

    belongs_to :organisation, MiwayCreditCore.Organisations.Organisation, type: :binary_id
    belongs_to :created_by, MiwayCreditCore.Accounts.User

    timestamps()
  end

  @doc "Changeset for creating/editing a product's terms. Never casts :status — use retire_changeset/1/activate_changeset/1 for that transition."
  def changeset(product, attrs) do
    product
    |> cast(attrs, [
      :organisation_id, :created_by_id, :name, :description,
      :minimum_principal, :maximum_principal,
      :interest_method, :interest_rate,
      :minimum_term_months, :maximum_term_months,
      :repayment_frequency,
      :origination_fee_percent, :late_payment_penalty_percent, :grace_period_days,
      :requires_collateral, :requires_guarantor, :minimum_guarantors, :requires_crb_check,
      :requires_affordability_check, :max_debt_to_income_percent,
      :minimum_approval_role,
      :effective_from, :effective_until
    ])
    |> validate_required([
      :organisation_id, :name,
      :minimum_principal, :maximum_principal,
      :interest_method, :interest_rate,
      :minimum_term_months, :maximum_term_months,
      :repayment_frequency, :effective_from
    ])
    |> validate_number(:minimum_principal, greater_than: 0)
    |> validate_number(:maximum_principal, greater_than: 0)
    |> validate_number(:interest_rate, greater_than_or_equal_to: 0)
    |> validate_number(:minimum_term_months, greater_than: 0)
    |> validate_number(:maximum_term_months, greater_than: 0)
    |> validate_number(:origination_fee_percent, greater_than_or_equal_to: 0)
    |> validate_number(:late_payment_penalty_percent, greater_than_or_equal_to: 0)
    |> validate_number(:grace_period_days, greater_than_or_equal_to: 0)
    |> validate_number(:minimum_guarantors, greater_than_or_equal_to: 0)
    |> validate_number(:max_debt_to_income_percent, greater_than: 0)
    |> validate_inclusion(:interest_method, @interest_methods)
    |> validate_inclusion(:repayment_frequency, @repayment_frequencies)
    |> validate_inclusion(:minimum_approval_role, @approval_roles ++ [nil])
    |> validate_principal_range()
    |> validate_term_range()
    |> validate_effective_range()
    |> unique_constraint([:organisation_id, :name])
    |> foreign_key_constraint(:organisation_id)
    |> foreign_key_constraint(:created_by_id)
  end

  def retire_changeset(product), do: change(product, status: "retired")
  def activate_changeset(product), do: change(product, status: "active")

  defp validate_principal_range(changeset) do
    validate_range(changeset, :minimum_principal, :maximum_principal)
  end

  defp validate_term_range(changeset) do
    validate_range(changeset, :minimum_term_months, :maximum_term_months)
  end

  defp validate_range(changeset, min_field, max_field) do
    min = get_field(changeset, min_field)
    max = get_field(changeset, max_field)

    cond do
      is_nil(min) or is_nil(max) -> changeset
      compare(min, max) == :gt -> add_error(changeset, max_field, "must be greater than or equal to #{min_field}")
      true -> changeset
    end
  end

  defp validate_effective_range(changeset) do
    from = get_field(changeset, :effective_from)
    until = get_field(changeset, :effective_until)

    if from && until && Date.compare(from, until) == :gt do
      add_error(changeset, :effective_until, "must be on or after effective_from")
    else
      changeset
    end
  end

  defp compare(%Decimal{} = a, %Decimal{} = b), do: Decimal.compare(a, b)
  defp compare(a, b) when is_integer(a) and is_integer(b), do: if(a > b, do: :gt, else: :lt)
end
