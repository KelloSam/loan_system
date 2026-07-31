defmodule MiwayCreditCore.Release do
  @moduledoc """
  Release tasks that run without Mix — invoked via
  `bin/miway_credit_core eval "MiwayCreditCore.Release.migrate"` since Mix
  and dev/test dependencies aren't present inside a compiled release.
  """

  @app :miway_credit_core

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Creates the first platform administrator for a freshly-migrated pilot
  database — the safe alternative to `priv/repo/seeds.exs`, which
  refuses to run in `:prod`. Reads credentials from operator-supplied
  env vars for this one invocation only; nothing is hardcoded.

      ADMIN_EMAIL=you@realdomain.com ADMIN_PASSWORD='...' \\
        bin/miway_credit_core eval "MiwayCreditCore.Release.create_platform_administrator"
  """
  def create_platform_administrator do
    load_app()
    {:ok, _} = Application.ensure_all_started(@app)

    email = System.fetch_env!("ADMIN_EMAIL")
    password = System.fetch_env!("ADMIN_PASSWORD")

    case MiwayCreditCore.Accounts.register_staff_member(
           %{email: email, password: password},
           "platform_administrator"
         ) do
      {:ok, user, _staff_member} ->
        IO.puts("Platform administrator created: #{user.email}")

      {:error, changeset} ->
        IO.puts(:stderr, "Could not create platform administrator: #{inspect(changeset.errors)}")
        System.halt(1)
    end
  end

  @doc """
  Runs a backup now — the release-safe equivalent of
  `mix miway_credit_core.backup`.

      bin/miway_credit_core eval "MiwayCreditCore.Release.run_backup"
  """
  def run_backup do
    load_app()
    {:ok, _} = Application.ensure_all_started(@app)

    case MiwayCreditCore.Backup.run() do
      {:ok, backup_id} ->
        IO.puts("Backup complete: #{backup_id}")

      {:error, reason} ->
        IO.puts(:stderr, "Backup failed: #{inspect(reason)}")
        System.halt(1)
    end
  end

  @doc """
  Runs a restore drill against the latest backup and prints a
  sanitized report — the release-safe equivalent of
  `mix miway_credit_core.restore_drill`. Never touches the real
  database or KYC directory.

      bin/miway_credit_core eval "MiwayCreditCore.Release.run_restore_drill"
  """
  def run_restore_drill do
    load_app()
    {:ok, _} = Application.ensure_all_started(@app)

    case MiwayCreditCore.Backup.run_restore_drill() do
      {:ok, %{overall_status: "ok"} = report} ->
        IO.puts(Jason.encode!(report, pretty: true))

      {:ok, report} ->
        IO.puts(:stderr, Jason.encode!(report, pretty: true))
        System.halt(1)

      {:error, report} ->
        IO.puts(:stderr, Jason.encode!(report, pretty: true))
        System.halt(1)
    end
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app, do: Application.load(@app)
end
