defmodule MiwayCreditCore.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Ecto repository
      MiwayCreditCore.Repo,

      # Start the PubSub system
      {Phoenix.PubSub, name: MiwayCreditCore.PubSub},

      # ETS storage backing the login rate limiter (RateLimitPlug)
      {PlugAttack.Storage.Ets, name: MiwayCreditCoreWeb.RateLimitStorage, clean_period: 60_000},

      # Start the Endpoint (HTTP server)
      MiwayCreditCoreWeb.Endpoint
    ] ++ arrears_scheduler_child()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MiwayCreditCore.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Configure Phoenix endpoint
  @impl true
  def config_change(changed, _new, removed) do
    MiwayCreditCoreWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Disabled in test (config/test.exs sets enabled: false) — a
  # background process querying the DB outside a test's checked-out
  # sandbox connection would error intermittently against async tests.
  defp arrears_scheduler_child do
    enabled? =
      Application.get_env(:miway_credit_core, MiwayCreditCore.ArrearsScheduler, [])
      |> Keyword.get(:enabled, true)

    if enabled?, do: [MiwayCreditCore.ArrearsScheduler], else: []
  end
end
