defmodule LoanSystem.MixProject do
  use Mix.Project

  def project do
    [
      app: :loan_system,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications
  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {LoanSystem.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies
  defp deps do
    [
      {:decimal, "~> 2.0"},        # For precise financial calculations
      {:ecto_sql, "~> 3.10"},      # For database operations
      {:postgrex, "~> 0.17.0"},    # For PostgreSQL support
      {:timex, "~> 3.7"},          # For date/time handling
      {:phoenix, "~> 1.7"},        # Phoenix web framework
      {:phoenix_ecto, "~> 4.4"},   # Phoenix and Ecto integration
      {:phoenix_html, "~> 3.3"},   # Phoenix HTML utilities
      {:phoenix_live_view, "~> 0.20"}, # Phoenix LiveView for interactive UI
      {:jason, "~> 1.4"},          # JSON parsing
      {:plug_cowboy, "~> 2.6"},      # HTTP server for Phoenix
      {:bcrypt_elixir, "~> 3.0"},  # Password hashing
      {:tzdata, "~> 1.1"},             # Timezone database (required by Tzdata.TimeZoneDatabase)
      {:phoenix_live_reload, "~> 1.4", only: :dev},  # Live code reloading in development
      {:ex_doc, "~> 0.29", only: :dev, runtime: false}  # For documentation
    ]
  end
end
