defmodule MiwayCreditCoreWeb.SystemHealthController do
  use MiwayCreditCoreWeb, :controller

  alias MiwayCreditCore.Backup
  alias MiwayCreditCore.Customers.DocumentStorage
  alias MiwayCreditCore.Monitoring
  alias MiwayCreditCoreWeb.Plugs.RequirePlatformAdminPlug

  # Genuinely platform-wide (not org-scoped) infrastructure data — see
  # RequirePlatformAdminPlug's moduledoc for why this can't be a normal
  # permission-catalog entry.
  plug RequirePlatformAdminPlug

  # 2x each scheduler's own default tick interval (ArrearsScheduler:
  # 1h, KycRetentionScheduler: 24h, BackupScheduler: 48h) — a
  # diagnostics threshold, not worth its own config surface.
  @staleness_thresholds_seconds %{
    arrears_scheduler: 2 * 60 * 60,
    kyc_retention_scheduler: 48 * 60 * 60,
    backup_scheduler: 48 * 60 * 60
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
      scanner_last_failure_at: Monitoring.last_scanner_failure_at(),
      pool_stats: Monitoring.pool_stats(),
      pool_healthy?: Monitoring.pool_healthy?(),
      kyc_disk: Monitoring.disk_free_bytes(DocumentStorage.root()),
      backup_failure_count: Monitoring.recent_backup_failure_count(),
      backup_last_failure_at: Monitoring.last_backup_failure_at(),
      latest_backup: Backup.latest_backup_info()
    )
  end
end
