defmodule MiwayCreditCore.KycRetentionScheduler do
  @moduledoc """
  Periodically purges the on-disk bytes of KYC documents whose
  retention window has elapsed
  (MiwayCreditCore.Customers.purge_expired_kyc_documents/0). Its own
  GenServer, not folded into ArrearsScheduler — different domain
  (Customers, not Lending/Collections), different cadence (daily is
  plenty; hourly would be wasteful for a purge job), and a different
  risk profile (an irreversible delete deserves its own blast radius,
  not shared with a more business-critical scheduler).

  Disabled in the test environment (config :miway_credit_core,
  __MODULE__, enabled: false) — same reasoning as ArrearsScheduler: a
  background process querying the DB outside a test's checked-out
  sandbox connection would error intermittently; the underlying query
  is unit-tested directly instead.

  The retention period itself (config :miway_credit_core,
  :kyc_retention_days) defaults to 2555 days (~7 years) — a common
  AML/KYC baseline in a number of jurisdictions, but NOT a legal
  determination. Confirm the real applicable regulation before relying
  on this in production.
  """

  use GenServer
  require Logger

  alias MiwayCreditCore.{Customers, AuditLogs}

  @default_interval_ms :timer.hours(24)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Process.send_after(self(), :purge_expired_kyc_documents, :timer.seconds(30))
    {:ok, %{interval_ms: interval_ms()}}
  end

  @impl true
  def handle_info(:purge_expired_kyc_documents, state) do
    purged = Customers.purge_expired_kyc_documents()

    if purged != [] do
      Logger.info("KycRetentionScheduler: purged #{length(purged)} document(s)")

      Enum.each(purged, fn document ->
        AuditLogs.log("kyc_document_purged",
          target_type: "kyc_document",
          target_id: document.id,
          organisation_id: document.organisation_id,
          metadata: %{customer_id: document.customer_id, document_type: document.document_type}
        )
      end)
    end

    MiwayCreditCore.Monitoring.record_tick(:kyc_retention_scheduler)

    Process.send_after(self(), :purge_expired_kyc_documents, state.interval_ms)
    {:noreply, state}
  end

  defp interval_ms do
    Application.get_env(:miway_credit_core, __MODULE__, [])
    |> Keyword.get(:interval_ms, @default_interval_ms)
  end
end
