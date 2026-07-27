defmodule MiwayCreditCoreWeb.ErrorJSON do
  @moduledoc "Renders error responses for the (currently unused) :api pipeline — standard mix phx.new pattern."

  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
