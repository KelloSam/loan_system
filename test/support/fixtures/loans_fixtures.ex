defmodule MiwayCreditCore.LoansFixtures do
  @moduledoc "Test helpers for creating MiwayCreditCore.Loans entities."

  import MiwayCreditCore.ClientsFixtures
  import MiwayCreditCore.AccountsFixtures

  @doc """
  Builds valid application attrs as string keys, matching what the real
  controllers submit (MiwayCreditCore.Loans.create_application/1 puts
  "risk_level"/"risk_score" in with string keys internally, so mixing
  atom/string keys here would break cast/3 — keep everything
  string-keyed like production does).
  """
  def valid_application_attrs(attrs \\ %{}) do
    client_id = attrs[:client_id] || attrs["client_id"] || client_fixture().id

    Enum.into(stringify_keys(attrs), %{
      "client_id" => client_id,
      # Deliberately not a round number — a round amount trips
      # FraudDetector's signal_round_amount and would make risk_level
      # unpredictable for tests that aren't about fraud scoring.
      "requested_amount" => "1234.56",
      "requested_term_months" => "6"
    })
  end

  def application_fixture(attrs \\ %{}) do
    {:ok, application} =
      attrs
      |> valid_application_attrs()
      |> MiwayCreditCore.Loans.create_application()

    application
  end

  @doc """
  An application_fixture/1 that's already approved — returns the
  LoanApplication struct with :loan_account preloaded, so callers can
  reach either `application.id` / `application.client_id` or
  `application.loan_account.id` / `.outstanding_balance` etc.
  """
  def approved_application_fixture(attrs \\ %{}) do
    application = application_fixture(attrs)
    admin = admin_fixture()
    {:ok, approved, account} = MiwayCreditCore.Loans.approve_application(application, admin.id)
    %{approved | loan_account: account}
  end

  def valid_payment_attrs(%MiwayCreditCore.Loans.LoanAccount{} = account, attrs \\ %{}) do
    recorder = admin_fixture()

    Enum.into(stringify_keys(attrs), %{
      "loan_account_id" => account.id,
      "amount" => "100.00",
      "received_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "method" => "cash",
      "recorded_by_id" => recorder.id
    })
  end

  def payment_fixture(%MiwayCreditCore.Loans.LoanAccount{} = account, attrs \\ %{}) do
    {:ok, transaction} =
      account
      |> valid_payment_attrs(attrs)
      |> MiwayCreditCore.Loans.record_payment()

    transaction
  end

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
