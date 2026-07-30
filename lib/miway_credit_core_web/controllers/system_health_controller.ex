defmodule MiwayCreditCoreWeb.SystemHealthController do
  use MiwayCreditCoreWeb, :controller

  alias MiwayCreditCore.Customers.DocumentStorage
  alias MiwayCreditCore.Monitoring
  alias MiwayCreditCoreWeb.Plugs.RequirePlatformAdminPlug

  # Genuinely platform-wide (not org-scoped) infrastructure data — see
  # RequirePlatformAdminPlug's moduledoc for why this can't be a normal
  # permission-catalog entry.
  plug RequirePlatformAdminPlug

  # 2x each scheduler's own default tick interval (ArrearsScheduler:
  # 1h, KycRetentionScheduler: 24h) — a diagnostics threshold, not
  # worth its own config surface.
  @staleness_thresholds_seconds %{
    arrears_scheduler: 2 * 60 * 60,
    kyc_retention_scheduler: 48 * 60 * 60
  }

  def show(conn, _params) do
    schedulers =
      for name <- Monitoring.scheduler_names() do
        threshold = Map.fetch!(@staleness_thresholds_seconds, name)

        %{
          name: name,
          last_tick: Monitoring.last_tick(name),
          stale?: Monitoring.stale?(name, threshold)
        }
      end

    render(conn, :show,
      schedulers: schedulers,
      scanner_failure_count: Monitoring.recent_scanner_failure_count(),
      pool_stats: Monitoring.pool_stats(),
      kyc_disk: Monitoring.disk_free_bytes(DocumentStorage.root())
    )
  end
end
