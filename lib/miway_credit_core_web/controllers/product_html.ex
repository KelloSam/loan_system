defmodule MiwayCreditCoreWeb.ProductHTML do
  use MiwayCreditCoreWeb, :html

  embed_templates "product_html/*"

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
