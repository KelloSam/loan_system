defmodule MiwayCreditCore.Monitoring.ErrorReporter.Default do
  @moduledoc "Logs a captured exception with a stable, greppable prefix — the default in every environment until a real adapter (Sentry, AppSignal, ...) is configured."

  @behaviour MiwayCreditCore.Monitoring.ErrorReporter

  require Logger

  @impl true
  def report(kind, reason, stacktrace, metadata) do
    status = Map.get(metadata, :status)

    Logger.error(
      "[error_reporter] #{kind} #{Exception.format_banner(kind, reason, stacktrace)} (status=#{inspect(status)})\n" <>
        Exception.format_stacktrace(stacktrace)
    )

    :ok
  end
end
