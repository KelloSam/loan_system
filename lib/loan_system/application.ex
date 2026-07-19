defmodule LoanSystem.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Ecto repository
      LoanSystem.Repo,

      # Start the PubSub system
      {Phoenix.PubSub, name: LoanSystem.PubSub},

      # ETS storage backing the login rate limiter (RateLimitPlug)
      {PlugAttack.Storage.Ets, name: LoanSystemWeb.RateLimitStorage, clean_period: 60_000},

      # Start the Endpoint (HTTP server)
      LoanSystemWeb.Endpoint
    ] ++ arrears_scheduler_child()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LoanSystem.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Configure Phoenix endpoint
  @impl true
  def config_change(changed, _new, removed) do
    LoanSystemWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Disabled in test (config/test.exs sets enabled: false) — a
  # background process querying the DB outside a test's checked-out
  # sandbox connection would error intermittently against async tests.
  defp arrears_scheduler_child do
    enabled? =
      Application.get_env(:loan_system, LoanSystem.ArrearsScheduler, [])
      |> Keyword.get(:enabled, true)

    if enabled?, do: [LoanSystem.ArrearsScheduler], else: []
  end
end
