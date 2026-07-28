defmodule MiwayCreditCore.Repo.Migrations.SeedChartOfAccountsForExistingOrganisations do
  @moduledoc """
  Step 14: every organisation created from now on gets its chart of
  accounts via `Authorization.provision_organisation/1` ->
  `GeneralLedger.seed_chart_of_accounts/1`. This backfills the same 9
  accounts for organisations that already existed before that wiring
  landed — the exact list duplicated here on purpose (migrations stay
  self-contained snapshots, not callers into application modules that
  may change later — same convention the contract_reference backfill
  migration already established).
  """

  use Ecto.Migration
  import Ecto.Query

  @chart_of_accounts [
    {"1000", "Cash", "asset"},
    {"1010", "Bank", "asset"},
    {"1020", "Mobile Money", "asset"},
    {"1030", "Suspense", "asset"},
    {"1100", "Loans Receivable", "asset"},
    {"4000", "Interest Income", "income"},
    {"4100", "Fee Income", "income"},
    {"4200", "Penalty Income", "income"},
    {"5000", "Bad Debt Expense", "expense"}
  ]

  def up do
    repo = repo()
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_naive()

    organisation_ids = repo.all(from(o in "organisations", select: o.id))

    # Raw (schema-less) selects return binary_id columns already in
    # their 16-byte binary form — Postgrex decodes `uuid` natively,
    # there's nothing to dump/cast here.
    rows =
      for organisation_id <- organisation_ids, {code, name, account_type} <- @chart_of_accounts do
        %{
          id: Ecto.UUID.bingenerate(),
          organisation_id: organisation_id,
          code: code,
          name: name,
          account_type: account_type,
          inserted_at: now,
          updated_at: now
        }
      end

    Enum.each(rows, fn row -> repo.insert_all("accounts", [row]) end)
  end

  def down do
    execute("DELETE FROM accounts")
  end
end
