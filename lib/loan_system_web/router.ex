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
    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; " <>
        "script-src 'self'; " <>
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; " <>
        "font-src 'self' https://fonts.gstatic.com; " <>
        "img-src 'self' data:; " <>
        "connect-src 'self' ws: wss:; " <>
        "frame-ancestors 'self'; " <>
        "base-uri 'self'; " <>
        "form-action 'self';"
    }
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

  pipeline :rate_limited do
    plug LoanSystemWeb.Plugs.RateLimitPlug
  end

  # Rate-limited (login POST only) — guards against credential-stuffing
  # across many accounts from a single IP.
  scope "/", LoanSystemWeb do
    pipe_through [:browser, :rate_limited]

    post "/login", SessionController, :create
  end

  # Public routes
  scope "/", LoanSystemWeb do
    pipe_through :browser

    get "/", SessionController, :new
    get "/login", SessionController, :new
    delete "/logout", SessionController, :delete
    get "/login/verify", TwoFactorController, :verify
    post "/login/verify", TwoFactorController, :confirm
  end

  # Admin routes
  scope "/admin", LoanSystemWeb do
    pipe_through [:browser, :auth, :ensure_admin]

    get "/dashboard", AdminDashboardController, :index
    get "/reports", ReportController, :index
    get "/reports/export.csv", ReportController, :export_csv
    get "/audit-logs", AuditLogController, :index
    get "/settings/2fa", TwoFactorController, :setup
    post "/settings/2fa/enable", TwoFactorController, :enable
    delete "/settings/2fa/disable", TwoFactorController, :disable
    resources "/clients", ClientController
    resources "/loans", LoanController
    patch "/loans/:id/approve", LoanController, :approve
    patch "/loans/:id/reject", LoanController, :reject
    post "/loans/:id/payments", LoanController, :create_payment
    post "/loans/:id/collateral", LoanController, :create_collateral
    delete "/loans/:id/collateral/:collateral_id", LoanController, :delete_collateral
  end

  # Client routes
  scope "/client", LoanSystemWeb do
    pipe_through [:browser, :auth, :ensure_client]

    get "/dashboard", ClientDashboardController, :index
    resources "/loans", ClientLoanController, only: [:index, :show]
  end
end
