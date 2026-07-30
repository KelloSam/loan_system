defmodule MiwayCreditCore.Monitoring.ErrorReporter do
  @moduledoc """
  Delivery boundary for captured exceptions, decoupling
  `MiwayCreditCore.Monitoring`'s `[:phoenix, :error_rendered]` handler
  from where a report actually goes — same swappable-adapter shape as
  `Accounts.PasswordResetNotifier`. `Default` (structured `Logger.error`)
  is the real, shippable adapter today, not a placeholder: there's no
  real Sentry/AppSignal account or dependency in this sandbox, so no
  such adapter is built, but this is the exact seam one would plug into
  later via `config :miway_credit_core, :error_reporter, MyAdapter`.
  """

  @callback report(kind :: term(), reason :: term(), stacktrace :: list(), metadata :: map()) ::
              :ok

  def report(kind, reason, stacktrace, metadata) do
    adapter().report(kind, reason, stacktrace, metadata)
  end

  defp adapter do
    Application.get_env(
      :miway_credit_core,
      :error_reporter,
      MiwayCreditCore.Monitoring.ErrorReporter.Default
    )
  end
end
