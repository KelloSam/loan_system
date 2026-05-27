defmodule LoanSystemWeb.ClientDashboardHTML do
  use LoanSystemWeb, :html
  use Phoenix.Component

  import Phoenix.HTML.Link

  embed_templates "client_dashboard_html/*"
end
