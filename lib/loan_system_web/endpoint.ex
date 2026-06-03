defmodule LoanSystemWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :loan_system

  @session_options [
    store: :cookie,
    key: "_loan_system_key",
    signing_salt: "loan_sys_sign",
    encryption_salt: "loan_sys_enc",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :loan_system,
    gzip: true,
    only: LoanSystemWeb.static_paths()

  if Mix.env() == :dev do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :loan_system
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug LoanSystemWeb.Router
end
