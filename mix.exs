defmodule MiwayCreditCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :miway_credit_core,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications
  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {MiwayCreditCore.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies
  defp deps do
    [
      # For precise financial calculations
      {:decimal, "~> 2.0"},
      # For database operations
      {:ecto_sql, "~> 3.10"},
      # For PostgreSQL support
      {:postgrex, "~> 0.17.0"},
      # For date/time handling
      {:timex, "~> 3.7"},
      # Phoenix web framework
      {:phoenix, "~> 1.7"},
      # Phoenix and Ecto integration
      {:phoenix_ecto, "~> 4.4"},
      # Phoenix HTML utilities
      {:phoenix_html, "~> 3.3"},
      # Phoenix LiveView for interactive UI
      {:phoenix_live_view, "~> 0.20"},
      # JSON parsing
      {:jason, "~> 1.4"},
      # HTTP server for Phoenix
      {:plug_cowboy, "~> 2.6"},
      # Password hashing
      {:bcrypt_elixir, "~> 3.0"},
      # Rate limiting on login
      {:plug_attack, "~> 0.4"},
      # TOTP 2FA (Google Authenticator compatible)
      {:nimble_totp, "~> 1.0"},
      # QR code SVG generation for 2FA setup
      {:eqrcode, "~> 0.2"},
      # Timezone database (required by Tzdata.TimeZoneDatabase)
      {:tzdata, "~> 1.1"},
      # Email composition/delivery (Notifications)
      {:swoosh, "~> 1.16"},
      # SMTP adapter backing Swoosh in production
      {:gen_smtp, "~> 1.2"},
      # Live code reloading in development
      {:phoenix_live_reload, "~> 1.4", only: :dev},
      # For documentation
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
      # Bundles assets/js/app.js for the browser
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      # Compiles assets/css/app.css
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev}
    ]
  end

  defp aliases do
    [
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind default", "esbuild default"],
      "assets.deploy": [
        "tailwind default --minify",
        "esbuild default --minify",
        "phx.digest"
      ]
    ]
  end
end
