defmodule LoanSystemWeb.AdminDashboardHTML do
  use LoanSystemWeb, :html
  use Phoenix.Component

  import Phoenix.HTML.Link

  embed_templates "admin_dashboard_html/*"
end
