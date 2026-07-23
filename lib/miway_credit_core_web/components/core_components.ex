defmodule MiwayCreditCoreWeb.CoreComponents do
  use Phoenix.Component

  def flash(assigns) do
    ~H"""
    <div class="flash">
      <%= render_slot(@inner_block) %>
    </div>
    """
  end
end
