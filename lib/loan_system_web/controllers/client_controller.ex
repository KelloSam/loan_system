defmodule LoanSystemWeb.ClientController do
  use LoanSystemWeb, :controller

  def index(conn, _params) do
    render(conn, :index)
  end
end
