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

  pipeline :ensure_staff do
    plug MiwayCreditCoreWeb.Plugs.EnsureStaffPlug
  end

  pipeline :ensure_customer do
    plug MiwayCreditCoreWeb.Plugs.EnsureCustomerPlug
  end

  pipeline :rate_limited do
    plug MiwayCreditCoreWeb.Plugs.RateLimitPlug
  end

  # Rate-limited (login and password-reset-request POSTs only) — guards
  # against credential-stuffing / reset-spam across many accounts from
  # a single IP.
  scope "/", MiwayCreditCoreWeb do
    pipe_through [:browser, :rate_limited]

    post "/login", SessionController, :create
    post "/password-reset", PasswordResetController, :create
  end

  # Public routes
  scope "/", MiwayCreditCoreWeb do
    pipe_through :browser

    get "/", SessionController, :new
    get "/login", SessionController, :new
    delete "/logout", SessionController, :delete
    get "/login/verify", TwoFactorController, :verify
    post "/login/verify", TwoFactorController, :confirm
    get "/password-reset", PasswordResetController, :new
    get "/password-reset/:token", PasswordResetController, :edit
    put "/password-reset/:token", PasswordResetController, :update
  end

  # Admin routes
  scope "/admin", MiwayCreditCoreWeb do
    pipe_through [:browser, :auth, :ensure_staff]

    get "/dashboard", AdminDashboardController, :index
    get "/reports", ReportController, :index
    get "/reports/export.csv", ReportController, :export_csv
    get "/audit-logs", AuditLogController, :index
    get "/settings/2fa", TwoFactorController, :setup
    post "/settings/2fa/enable", TwoFactorController, :enable
    delete "/settings/2fa/disable", TwoFactorController, :disable
    resources "/customers", CustomerController
    post "/customers/:id/next_of_kin", CustomerController, :create_next_of_kin
    delete "/customers/:id/next_of_kin/:next_of_kin_id", CustomerController, :delete_next_of_kin
    post "/customers/:id/guarantors", CustomerController, :create_guarantor
    delete "/customers/:id/guarantors/:guarantor_id", CustomerController, :delete_guarantor
    post "/customers/:id/kyc_documents", CustomerController, :create_kyc_document
    get "/customers/:id/kyc_documents/:document_id/download", CustomerController, :download_kyc_document
    delete "/customers/:id/kyc_documents/:document_id", CustomerController, :remove_kyc_document
    post "/customers/:id/consents", CustomerController, :create_consent
    delete "/customers/:id/consents/:consent_id", CustomerController, :revoke_consent
    patch "/customers/:id/kyc/submit", CustomerController, :submit_kyc_review
    patch "/customers/:id/kyc/verify", CustomerController, :verify_kyc
    patch "/customers/:id/kyc/reject", CustomerController, :reject_kyc
    resources "/loans", LoanController
    patch "/loans/:id/approve", LoanController, :approve
    patch "/loans/:id/reject", LoanController, :reject
    post "/loans/:id/payments", LoanController, :create_payment
    patch "/loans/:id/payments/:transaction_id/void", LoanController, :void_payment
    post "/loans/:id/collateral", LoanController, :create_collateral
    delete "/loans/:id/collateral/:collateral_id", LoanController, :delete_collateral
  end

  # Customer portal routes — path stays "/client" (naming predates the
  # identity split); the controllers underneath are Customers-domain,
  # hence the Customer* naming. Gated on CustomerUser (a real link to
  # a Customer record), not a role string.
  scope "/client", MiwayCreditCoreWeb do
    pipe_through [:browser, :auth, :ensure_customer]

    get "/dashboard", CustomerDashboardController, :index
    resources "/loans", CustomerLoanController, only: [:index, :show]
  end
end
