defmodule LoanSystemWeb.LoanHTML do
  use LoanSystemWeb, :html

  embed_templates "loan_html/*"

  def risk_badge_class("high"),   do: "bg-red-100 text-red-700 border border-red-200"
  def risk_badge_class("medium"), do: "bg-amber-100 text-amber-700 border border-amber-200"
  def risk_badge_class(_),        do: "bg-green-50 text-green-700 border border-green-200"

  def status_class("approved"),  do: "bg-green-100 text-green-800"
  def status_class("pending"),   do: "bg-yellow-100 text-yellow-800"
  def status_class("rejected"),  do: "bg-red-100 text-red-800"
  def status_class("completed"), do: "bg-blue-100 text-blue-800"
  def status_class("paid"),      do: "bg-green-100 text-green-800"
  def status_class("overdue"),   do: "bg-red-100 text-red-800"
  def status_class(_),           do: "bg-gray-100 text-gray-800"

  def error_tag(form, field) do
    form.errors
    |> Keyword.get_values(field)
    |> Enum.map(fn {msg, opts} ->
      translated =
        Enum.reduce(opts, msg, fn
          {key, value}, acc when is_binary(value) -> String.replace(acc, "%{#{key}}", value)
          {key, value}, acc -> String.replace(acc, "%{#{key}}", to_string(value))
        end)

      Phoenix.HTML.raw(~s(<span class="mt-1 block text-xs text-red-600">#{translated}</span>))
    end)
  end
end
