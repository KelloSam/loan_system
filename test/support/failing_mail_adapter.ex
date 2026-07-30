defmodule MiwayCreditCore.Support.FailingMailAdapter do
  @moduledoc """
  Always fails delivery. Injected per-call via `Notifications`'s
  `mailer_opts` (Swoosh dynamic config), not global Application
  config — this codebase already has one documented flakiness lesson
  from mutating shared/global config inside the async suite (see
  Step 17's PlugAttack ETS counter), so failure-path tests avoid it
  entirely rather than repeat it.
  """
  use Swoosh.Adapter

  def deliver(_email, _config), do: {:error, :provider_unreachable}
end
