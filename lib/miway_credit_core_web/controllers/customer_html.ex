defmodule MiwayCreditCoreWeb.CustomerHTML do
  use MiwayCreditCoreWeb, :html

  embed_templates "customer_html/*"

  def loan_status_class("approved"),  do: "bg-green-100 text-green-800"
  def loan_status_class("pending"),   do: "bg-yellow-100 text-yellow-800"
  def loan_status_class("rejected"),  do: "bg-red-100 text-red-800"
  def loan_status_class("completed"), do: "bg-blue-100 text-blue-800"
  def loan_status_class(_),           do: "bg-gray-100 text-gray-800"

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
