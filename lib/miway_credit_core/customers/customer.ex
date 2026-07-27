defmodule MiwayCreditCore.Customers.Customer do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  This module handles customer-related functionality.
  
  A customer represents a person who can request loans in the system.
  This module provides functions to create, validate, and manage customers.
  
  ## Examples
      
      iex> alias MiwayCreditCore.Customers.Customer
      iex> {:ok, customer} = Customer.new(%{name: "John Doe", phone: "260123456789", id_number: "123456/78/9"})
      iex> customer.name
      "John Doe"
  """

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "customers" do
    field :name, :string
    field :phone, :string
    field :id_number, :string
    field :email, :string
    field :address, :string
    field :active, :boolean, default: true
    field :total_loans, :integer, default: 0
    field :current_balance, :decimal, default: Decimal.new("0.00")

    belongs_to :organisation, MiwayCreditCore.Organisations.Organisation, type: :binary_id

    has_many :loan_applications, MiwayCreditCore.Applications.LoanApplication
    has_many :loan_accounts, MiwayCreditCore.Lending.LoanAccount

    timestamps()
  end
  # Use Decimal for precise financial operations
  # --------------------------------------------------------------
  # TYPE SPECIFICATIONS
  # --------------------------------------------------------------
  # Type specs help document what types of data your functions accept
  # and return. They're used by tools like Dialyzer for static analysis.
  # --------------------------------------------------------------
  
  # Define a type for our customer struct
  @type t() :: %__MODULE__{
    id: binary(),
    organisation_id: binary(),
    name: String.t(),
    phone: String.t(),
    id_number: String.t(),
    email: String.t() | nil,
    address: String.t() | nil,
    inserted_at: DateTime.t() | nil,
    updated_at: DateTime.t() | nil,
    active: boolean(),
    total_loans: non_neg_integer(),
    current_balance: Decimal.t() | nil,
    loan_applications: [MiwayCreditCore.Applications.LoanApplication.t()] | Ecto.Association.NotLoaded.t(),
    loan_accounts: [MiwayCreditCore.Lending.LoanAccount.t()] | Ecto.Association.NotLoaded.t()
  }
  # Define a type for customer creation params
  @type customer_params() :: %{
    required(:name) => String.t(),
    required(:phone) => String.t(),
    required(:id_number) => String.t(),
    optional(:email) => String.t(),
    optional(:address) => String.t()
  }
  
  # Define a type for validation result
  @type validation_result() :: {:ok, t()} | {:error, keyword()}
  
  # --------------------------------------------------------------
  # PUBLIC FUNCTIONS
  # --------------------------------------------------------------
  
  @doc """
  Creates a new customer from the provided parameters.
  
  ## Parameters
    * `params` - A map containing customer information
    
  ## Returns
    * `{:ok, customer}` - If validation succeeds
    * `{:error, changeset}` - If validation fails
    
  ## Examples
      
      iex> Customer.new(%{name: "Jane Doe", phone: "260987654321", id_number: "987654/32/1"})
      {:ok, %Customer{name: "Jane Doe", phone: "260987654321", id_number: "987654/32/1"}}
      
      iex> Customer.new(%{name: "", phone: "123", id_number: ""})
      {:error, %Ecto.Changeset{}}
  """
  @spec new(customer_params()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def new(params) do
    %__MODULE__{}
    |> changeset(params)
    |> case do
      %{valid?: true} = changeset ->
        {:ok, Ecto.Changeset.apply_changes(changeset)}
      changeset ->
        {:error, changeset}
    end
  end
  @doc """
  Creates a changeset for customer.
  
  ## Parameters
    * `customer` - Existing customer struct or %Customer{}
    * `attrs` - Map of attributes to change
    
  ## Validations
    * Required fields: name, phone, id_number
    * Phone number must:
      - Start with "26" or "260"
      - Have at least 9 digits
      - Contain only numbers
    * Email must have a valid format (when provided)
    * Phone, ID number, and email must be unique
    
  ## Returns
    * Changeset
  """
  def changeset(customer, attrs) do
    customer
    |> cast(attrs, [
      :organisation_id,
      :name,
      :phone,
      :id_number,
      :email,
      :address,
      :active,
      :total_loans,
      :current_balance
    ])
    |> validate_required([:organisation_id, :name, :phone, :id_number])
    |> validate_phone_format()
    |> validate_format(:email, ~r/^[^@\s]+@[^@\s]+\.[^@\s]+$/, message: "must have a valid format")
    |> unique_constraint(:phone)
    |> unique_constraint(:id_number)
    |> unique_constraint(:email)
    |> foreign_key_constraint(:organisation_id)
  end
  
  # Custom validator for phone format
  defp validate_phone_format(changeset) do
    validate_change(changeset, :phone, fn :phone, phone ->
      if valid_phone?(phone), do: [], else: [phone: "invalid format"]
    end)
  end
  # --------------------------------------------------------------
  # PRIVATE FUNCTIONS
  # --------------------------------------------------------------
  # Private functions are only accessible within the module
  # In Elixir, we mark private functions with `defp` instead of `def`
  # --------------------------------------------------------------
  defp valid_phone?(phone) when is_binary(phone) do
    # Matches numbers starting with 26 or 260 followed by at least 7 digits
    # The outer anchors ensure the entire string is digits only
    Regex.match?(~r/^(26|260)\d{7,}$/, phone)
  end
  defp valid_phone?(_), do: false
end
