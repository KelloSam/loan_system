defmodule LoanSystemWeb.Router do
  use Phoenix.Router
  import Plug.Conn
  import Phoenix.Controller
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LoanSystemWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :auth do
    plug LoanSystemWeb.Plugs.AuthPlug
  end

  pipeline :ensure_admin do
    plug LoanSystemWeb.Plugs.EnsureRolePlug, "admin"
  end

  pipeline :ensure_client do
    plug LoanSystemWeb.Plugs.EnsureRolePlug, "client"
  end

  # Public routes
  scope "/", LoanSystemWeb do
    pipe_through :browser

    get "/", SessionController, :new
    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
  end

  # Admin routes
  scope "/admin", LoanSystemWeb do
    pipe_through [:browser, :auth, :ensure_admin]

    get "/dashboard", AdminDashboardController, :index
    get "/audit-logs", AuditLogController, :index
    resources "/clients", ClientController
    resources "/loans", LoanController
    patch "/loans/:id/approve", LoanController, :approve
    patch "/loans/:id/reject", LoanController, :reject
    post "/loans/:id/payments", LoanController, :create_payment
  end

  # Client routes
  scope "/client", LoanSystemWeb do
    pipe_through [:browser, :auth, :ensure_client]

    get "/dashboard", ClientDashboardController, :index
    resources "/loans", ClientLoanController, only: [:index, :show]
  end
end
