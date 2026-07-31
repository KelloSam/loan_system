defmodule Mix.Tasks.MiwayCreditCore.RestoreDrill do
  @moduledoc """
  Restores the latest (or a named) backup into a fresh scratch
  database and KYC directory, verifies it against the backup's own
  manifest, and prints a sanitized report. Never touches the real
  database or KYC directory.

      mix miway_credit_core.restore_drill
      mix miway_credit_core.restore_drill --backup-id=20260731T000000Z
  """

  use Mix.Task

  alias MiwayCreditCore.Backup

  @shortdoc "Runs a restore drill against a fresh scratch database"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _rest, _invalid} = OptionParser.parse(args, strict: [backup_id: :string])
    backup_id = Keyword.get(opts, :backup_id, :latest)

    case Backup.run_restore_drill(backup_id) do
      {:ok, %{overall_status: "ok"} = report} ->
        Mix.shell().info(Jason.encode!(report, pretty: true))

      {:ok, report} ->
        # overall_status: "mismatch" — the drill ran to completion but
        # found a real integrity problem. Still a failure exit code.
        Mix.shell().error(Jason.encode!(report, pretty: true))
        System.halt(1)

      {:error, report} when is_map(report) ->
        Mix.shell().error(Jason.encode!(report, pretty: true))
        System.halt(1)

      {:error, reason} ->
        Mix.shell().error("Restore drill failed: #{inspect(reason)}")
        System.halt(1)
    end
  end
end
