defmodule MiwayCreditCoreWeb.AuditLogHTML do
  use MiwayCreditCoreWeb, :html
  embed_templates "audit_log_html/*"

  def format_event(event) do
    event |> String.replace("_", " ") |> String.capitalize()
  end

  def event_color(event) do
    cond do
      String.ends_with?(event, ["_approved", "_verified", "_success"]) -> "text-green-700 bg-green-50"
      String.ends_with?(event, ["_rejected", "_failure", "_failed", "_removed", "_deleted"]) -> "text-red-600 bg-red-50"
      String.starts_with?(event, "payment_") -> "text-gold-700 bg-gold-50"
      String.starts_with?(event, ["loan_application_", "loan_account_"]) -> "text-navy-700 bg-navy-50"
      true -> "text-gray-600 bg-gray-100"
    end
  end
end
