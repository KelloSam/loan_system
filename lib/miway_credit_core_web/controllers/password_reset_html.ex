defmodule MiwayCreditCoreWeb.PasswordResetHTML do
  use MiwayCreditCoreWeb, :html
  import Phoenix.HTML.Form
  import Phoenix.Flash

  embed_templates "password_reset_html/*"
end
