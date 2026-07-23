defmodule MiwayCreditCoreWeb.PageController do
  use MiwayCreditCoreWeb, :controller

  def home(conn, _params) do
    render(conn, :home, layout: false)
  end
end
