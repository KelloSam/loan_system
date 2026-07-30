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

  # Liveness/readiness checks for load balancers / uptime monitors — no
  # session, CSRF, or CSP machinery needed for this.
  scope "/", MiwayCreditCoreWeb do
    pipe_through :api

    get "/up", HealthController, :show
    get "/ready", HealthController, :ready
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

  # Rate-limited (login, TOTP-verify, and password-reset-request POSTs
  # only) — guards against credential-stuffing / TOTP brute-forcing /
  # reset-spam across many accounts from a single IP.
  scope "/", MiwayCreditCoreWeb do
    pipe_through [:browser, :rate_limited]

    post "/login", SessionController, :create
    post "/login/verify", TwoFactorController, :confirm
    post "/password-reset", PasswordResetController, :create
  end

  # Public routes
  scope "/", MiwayCreditCoreWeb do
    pipe_through :browser

    get "/", SessionController, :new
    get "/login", SessionController, :new
    delete "/logout", SessionController, :delete
    get "/login/verify", TwoFactorController, :verify
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
    get "/audit-logs/export.csv", AuditLogController, :export_csv
    get "/settings/2fa", TwoFactorController, :setup
    post "/settings/2fa/enable", TwoFactorController, :enable
    delete "/settings/2fa/disable", TwoFactorController, :disable
    resources "/customers", CustomerController
    post "/customers/:id/next_of_kin", CustomerController, :create_next_of_kin
    delete "/customers/:id/next_of_kin/:next_of_kin_id", CustomerController, :delete_next_of_kin
    post "/customers/:id/guarantors", CustomerController, :create_guarantor
    delete "/customers/:id/guarantors/:guarantor_id", CustomerController, :delete_guarantor
    post "/customers/:id/credit_reports", CustomerController, :create_credit_report
    post "/customers/:id/kyc_documents", CustomerController, :create_kyc_document
    get "/customers/:id/kyc_documents/:document_id/download", CustomerController, :download_kyc_document
    delete "/customers/:id/kyc_documents/:document_id", CustomerController, :remove_kyc_document
    post "/customers/:id/consents", CustomerController, :create_consent
    delete "/customers/:id/consents/:consent_id", CustomerController, :revoke_consent
    patch "/customers/:id/kyc/submit", CustomerController, :submit_kyc_review
    patch "/customers/:id/kyc/verify", CustomerController, :verify_kyc
    patch "/customers/:id/kyc/reject", CustomerController, :reject_kyc
    resources "/products", ProductController, except: [:show, :delete]
    patch "/products/:id/retire", ProductController, :retire
    patch "/products/:id/activate", ProductController, :activate
    resources "/branches", BranchController, except: [:show, :delete]
    resources "/loans", LoanController
    patch "/loans/:id/assess", LoanController, :assess
    patch "/loans/:id/approve", LoanController, :approve
    patch "/loans/:id/reject", LoanController, :reject
    patch "/loans/:id/conditionally_approve", LoanController, :conditionally_approve
    patch "/loans/:id/refer", LoanController, :refer
    patch "/loans/:id/clear_conditions", LoanController, :clear_conditions
    patch "/loans/:id/disburse", LoanController, :disburse
    patch "/loans/:id/reverse_disbursement", LoanController, :reverse_disbursement
    patch "/loans/:id/withdraw", LoanController, :withdraw
    post "/loans/:id/payments", LoanController, :create_payment
    post "/loans/:id/payments/failed", LoanController, :record_failed_payment
    patch "/loans/:id/payments/:transaction_id/void", LoanController, :void_payment
    patch "/loans/:id/payments/:transaction_id/fail", LoanController, :fail_payment
    get "/loans/:id/payments/:transaction_id/receipt", LoanController, :receipt
    post "/loans/:id/collateral", LoanController, :create_collateral
    delete "/loans/:id/collateral/:collateral_id", LoanController, :delete_collateral

    post "/loans/:id/collections/activities", CollectionController, :create_activity
    post "/loans/:id/collections/promises", CollectionController, :create_promise
    patch "/loans/:id/collections/escalate", CollectionController, :escalate_case
    patch "/loans/:id/collections/close", CollectionController, :close_case
    patch "/loans/:id/collections/recovery_status", CollectionController, :set_recovery_status
    post "/loans/:id/restructuring_requests", CollectionController, :create_restructuring_request
    patch "/loans/:id/restructuring_requests/:request_id/approve", CollectionController, :approve_restructuring
    patch "/loans/:id/restructuring_requests/:request_id/reject", CollectionController, :reject_restructuring
    post "/loans/:id/write_off_requests", CollectionController, :create_write_off_request
    patch "/loans/:id/write_off_requests/:request_id/approve", CollectionController, :approve_write_off
    patch "/loans/:id/write_off_requests/:request_id/reject", CollectionController, :reject_write_off
  end

  if Application.compile_env(:miway_credit_core, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
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
