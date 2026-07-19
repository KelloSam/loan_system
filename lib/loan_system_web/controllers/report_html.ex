defmodule LoanSystemWeb.ReportHTML do
  use LoanSystemWeb, :html
  use Phoenix.Component

  import Phoenix.HTML.Link

  embed_templates "report_html/*"
end
