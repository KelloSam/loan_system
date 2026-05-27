defmodule LoanSystemWeb.ClientLoanController do
  use LoanSystemWeb, :controller

  def index(conn, _params) do
    render(conn, :index)
  end

  def show(conn, %{"id" => _id}) do
    render(conn, :show)
  end
end
