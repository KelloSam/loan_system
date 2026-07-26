defmodule MiwayCreditCoreWeb.Router do
  use Phoenix.Router
  import Plug.Conn
  import Phoenix.Controller
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MiwayCreditCoreWeb.Layouts, :root}
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
    plug MiwayCreditCoreWeb.Plugs.AuthPlug
  end

  pipeline :ensure_admin do
    plug MiwayCreditCoreWeb.Plugs.EnsureRolePlug, "admin"
  end

  pipeline :ensure_client do
    plug MiwayCreditCoreWeb.Plugs.EnsureRolePlug, "client"
  end

  pipeline :rate_limited do
    plug MiwayCreditCoreWeb.Plugs.RateLimitPlug
  end

  # Rate-limited (login POST only) — guards against credential-stuffing
  # across many accounts from a single IP.
  scope "/", MiwayCreditCoreWeb do
    pipe_through [:browser, :rate_limited]

    post "/login", SessionController, :create
  end

  # Public routes
  scope "/", MiwayCreditCoreWeb do
    pipe_through :browser

    get "/", SessionController, :new
    get "/login", SessionController, :new
    delete "/logout", SessionController, :delete
    get "/login/verify", TwoFactorController, :verify
    post "/login/verify", TwoFactorController, :confirm
  end

  # Admin routes
  scope "/admin", MiwayCreditCoreWeb do
    pipe_through [:browser, :auth, :ensure_admin]

    get "/dashboard", AdminDashboardController, :index
    get "/reports", ReportController, :index
    get "/reports/export.csv", ReportController, :export_csv
    get "/audit-logs", AuditLogController, :index
    get "/settings/2fa", TwoFactorController, :setup
    post "/settings/2fa/enable", TwoFactorController, :enable
    delete "/settings/2fa/disable", TwoFactorController, :disable
    resources "/customers", CustomerController
    resources "/loans", LoanController
    patch "/loans/:id/approve", LoanController, :approve
    patch "/loans/:id/reject", LoanController, :reject
    post "/loans/:id/payments", LoanController, :create_payment
    patch "/loans/:id/payments/:transaction_id/void", LoanController, :void_payment
    post "/loans/:id/collateral", LoanController, :create_collateral
    delete "/loans/:id/collateral/:collateral_id", LoanController, :delete_collateral
  end

  # Customer portal routes — path stays "/client" to match the "client"
  # auth role (MiwayCreditCore.Accounts concern); the controllers
  # underneath are Customers-domain, hence the Customer* naming.
  scope "/client", MiwayCreditCoreWeb do
    pipe_through [:browser, :auth, :ensure_client]

    get "/dashboard", CustomerDashboardController, :index
    resources "/loans", CustomerLoanController, only: [:index, :show]
  end
end
