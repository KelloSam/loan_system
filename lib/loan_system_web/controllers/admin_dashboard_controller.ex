defmodule LoanSystemWeb.AdminDashboardController do
  use LoanSystemWeb, :controller

  def index(conn, _params) do
    render(conn, :index)
  end

  def new(conn, _params) do
    render(conn, :new)
  end
  
  def create(conn, _params) do
    # Logic for creating a new admin dashboard entry
    # This is just a placeholder; actual logic will depend on your application
    conn
    |> put_flash(:info, "Admin dashboard entry created successfully.")
    |> redirect(to: ~p"/admin/dashboard")
  end
end
