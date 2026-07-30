defmodule MiwayCreditCoreWeb.SystemHealthHTML do
  use MiwayCreditCoreWeb, :html
  embed_templates "system_health_html/*"

  def format_scheduler_name(:arrears_scheduler), do: "Arrears Scheduler"
  def format_scheduler_name(:kyc_retention_scheduler), do: "KYC Retention Scheduler"

  def format_last_tick(:never), do: "Never ticked"

  def format_last_tick({:ok, %DateTime{} = last}) do
    Calendar.strftime(last, "%d %b %Y %H:%M:%S UTC")
  end

  def format_bytes({:error, :path_not_found}), do: "Directory not found"
  def format_bytes({:error, _reason}), do: "Unavailable"

  def format_bytes({:ok, bytes}) when bytes >= 1_073_741_824 do
    "#{Float.round(bytes / 1_073_741_824, 1)} GB free"
  end

  def format_bytes({:ok, bytes}) when bytes >= 1_048_576 do
    "#{Float.round(bytes / 1_048_576, 1)} MB free"
  end

  def format_bytes({:ok, bytes}), do: "#{bytes} bytes free"

  def status_badge_class(true), do: "badge badge-rejected"
  def status_badge_class(false), do: "badge badge-disbursed"
end
