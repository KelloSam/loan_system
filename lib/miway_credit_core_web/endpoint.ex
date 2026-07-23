defmodule MiwayCreditCoreWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :miway_credit_core

  @session_options [
    store: :cookie,
    key: "_miway_credit_core_key",
    signing_salt: "loan_sys_sign",
    encryption_salt: "loan_sys_enc",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :miway_credit_core,
    gzip: true,
    only: MiwayCreditCoreWeb.static_paths()

  if Mix.env() == :dev do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :miway_credit_core
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
  plug MiwayCreditCoreWeb.Router
end
