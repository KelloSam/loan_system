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

      # Start the Endpoint (HTTP server)
      LoanSystemWeb.Endpoint
    ]

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
end
