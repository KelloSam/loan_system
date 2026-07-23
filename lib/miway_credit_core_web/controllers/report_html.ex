defmodule MiwayCreditCoreWeb.ReportHTML do
  use MiwayCreditCoreWeb, :html
  use Phoenix.Component

  import Phoenix.HTML.Link

  embed_templates "report_html/*"
end
