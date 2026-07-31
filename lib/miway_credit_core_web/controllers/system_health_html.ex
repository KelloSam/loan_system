defmodule MiwayCreditCoreWeb.SystemHealthHTML do
  use MiwayCreditCoreWeb, :html
  embed_templates "system_health_html/*"

  def format_scheduler_name(:arrears_scheduler), do: "Arrears Scheduler"
  def format_scheduler_name(:kyc_retention_scheduler), do: "KYC Retention Scheduler"
  def format_scheduler_name(:backup_scheduler), do: "Backup Scheduler"

  def format_last_tick(:never), do: "Never ticked"
  def format_last_tick({:ok, %DateTime{}} = timestamp), do: format_timestamp(timestamp)

  def format_timestamp(:never), do: "n/a"

  def format_timestamp({:ok, %DateTime{} = value}),
    do: Calendar.strftime(value, "%d %b %Y %H:%M:%S UTC")

  def format_bytes({:error, :path_not_found}), do: "Directory not found"
  def format_bytes({:error, _reason}), do: "Unavailable"

  def format_bytes({:ok, bytes}) when bytes >= 1_073_741_824 do
    "#{Float.round(bytes / 1_073_741_824, 1)} GB free"
  end

  def format_bytes({:ok, bytes}) when bytes >= 1_048_576 do
    "#{Float.round(bytes / 1_048_576, 1)} MB free"
  end

  def format_bytes({:ok, bytes}), do: "#{bytes} bytes free"

  def format_last_failure(:never), do: "No failures recorded"

  def format_last_failure({:ok, %DateTime{} = last}) do
    "Last failure: #{Calendar.strftime(last, "%d %b %Y %H:%M:%S UTC")}"
  end

  def format_backup_summary(:unavailable), do: "No backup recorded yet"

  def format_backup_summary(%{backup_id: backup_id, size_bytes: size_bytes}) do
    "#{backup_id} · #{format_size(size_bytes)}"
  end

  defp format_size(bytes) when bytes >= 1_073_741_824,
    do: "#{Float.round(bytes / 1_073_741_824, 1)} GB"

  defp format_size(bytes) when bytes >= 1_048_576, do: "#{Float.round(bytes / 1_048_576, 1)} MB"
  defp format_size(bytes), do: "#{bytes} bytes"

  def status_badge_class(true), do: "badge badge-rejected"
  def status_badge_class(false), do: "badge badge-disbursed"
end
