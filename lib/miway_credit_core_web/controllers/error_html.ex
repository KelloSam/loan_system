defmodule MiwayCreditCoreWeb.ErrorHTML do
  @moduledoc """
  Renders error pages — the standard `mix phx.new` pattern. This app
  had no error view at all until Step 5's cross-organisation isolation
  work needed a real 404 for an out-of-scope record instead of a raw
  exception, which is what surfaced the gap.

  See config/config.exs for the render_errors wiring and
  https://hexdocs.pm/phoenix/Phoenix.Controller.html#action_fallback/1
  """
  use MiwayCreditCoreWeb, :html

  embed_templates "error_html/*"

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
