defmodule MiwayCreditCore.LoansFixtures do
  @moduledoc "Test helpers for creating MiwayCreditCore.Loans entities."

  import MiwayCreditCore.CustomersFixtures
  import MiwayCreditCore.AccountsFixtures

  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.Customers.Customer
  alias MiwayCreditCore.Accounts.Scope

  @doc """
  Builds valid application attrs as string keys, matching what the real
  controllers submit (MiwayCreditCore.Applications.create_application/1
  puts "risk_level"/"risk_score" in with string keys internally, so
  mixing atom/string keys here would break cast/3 — keep everything
  string-keyed like production does).
  """
  def valid_application_attrs(attrs \\ %{}) do
    customer_id = attrs[:customer_id] || attrs["customer_id"] || customer_fixture().id

    Enum.into(stringify_keys(attrs), %{
      "customer_id" => customer_id,
      # Deliberately not a round number — a round amount trips
      # FraudDetector's signal_round_amount and would make risk_level
      # unpredictable for tests that aren't about fraud scoring.
      "requested_amount" => "1234.56",
      "requested_term_months" => "6"
    })
  end

  @doc "Scope matching whichever customer this application is (or will be) filed under."
  def scope_for_customer_id(customer_id) do
    %Scope{organisation_id: Repo.get!(Customer, customer_id).organisation_id}
  end

  def application_fixture(attrs \\ %{}) do
    attrs = valid_application_attrs(attrs)
    scope = scope_for_customer_id(attrs["customer_id"])

    {:ok, application} = MiwayCreditCore.Applications.create_application(scope, attrs)
    application
  end

  @doc """
  An application_fixture/1 that's already approved — returns the
  LoanApplication struct with :loan_account preloaded, so callers can
  reach either `application.id` / `application.customer_id` or
  `application.loan_account.id` / `.outstanding_balance` etc.
  """
  def approved_application_fixture(attrs \\ %{}) do
    application = application_fixture(attrs)
    admin = admin_fixture()
    {:ok, approved, account} = MiwayCreditCore.Applications.approve_application(application, admin.id)
    %{approved | loan_account: account}
  end

  def valid_payment_attrs(%MiwayCreditCore.Lending.LoanAccount{} = account, attrs \\ %{}) do
    recorder = admin_fixture()

    Enum.into(stringify_keys(attrs), %{
      "loan_account_id" => account.id,
      "amount" => "100.00",
      "received_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "method" => "cash",
      "recorded_by_id" => recorder.id
    })
  end

  def payment_fixture(%MiwayCreditCore.Lending.LoanAccount{} = account, attrs \\ %{}) do
    scope = %Scope{organisation_id: account.organisation_id}

    {:ok, transaction} =
      account
      |> valid_payment_attrs(attrs)
      |> then(&MiwayCreditCore.Payments.record_payment(scope, &1))

    transaction
  end

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
