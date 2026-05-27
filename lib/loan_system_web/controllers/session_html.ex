defmodule LoanSystemWeb.SessionHTML do
  use LoanSystemWeb, :html
  import Phoenix.HTML.Form
  import Phoenix.Flash

  embed_templates "session_html/*"
end
