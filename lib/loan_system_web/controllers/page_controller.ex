defmodule LoanSystemWeb.PageController do
  use LoanSystemWeb, :controller

  def home(conn, _params) do
    render(conn, :home, layout: false)
  end
end
