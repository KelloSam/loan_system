defmodule MiwayCreditCoreWeb.SessionHTML do
  use MiwayCreditCoreWeb, :html
  import Phoenix.HTML.Form
  import Phoenix.Flash

  embed_templates "session_html/*"
end
