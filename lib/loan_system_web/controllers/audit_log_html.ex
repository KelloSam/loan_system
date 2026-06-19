defmodule LoanSystemWeb.AuditLogHtml do
  use LoanSystemWeb, :html
  embed_templates "audit_log_html/*"

  def format_event(event) do
    event |> String.replace("_", " ") |> String.capitalize()
  end

  def event_color("login_failure"), do: "text-red-600 bg-red-50"
  def event_color("loan_approved"), do: "text-green-700 bg-green-50"
  def event_color("loan_rejected"), do: "text-red-600 bg-red-50"
  def event_color("loan_created"), do: "text-navy-700 bg-navy-50"
  def event_color("payment_recorded"), do: "text-gold-700 bg-gold-50"
  def event_color(_), do: "text-gray-600 bg-gray-100"
end
