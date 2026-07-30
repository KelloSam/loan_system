defmodule MiwayCreditCore.Notifications.Mailer do
  @moduledoc """
  The single Swoosh mailer for the app. Adapter is environment-config
  only (`Swoosh.Adapters.Local` in dev, `Swoosh.Adapters.Test` in test,
  `Swoosh.Adapters.SMTP` in prod once `SMTP_HOST` is set — see
  config/runtime.exs) — no context ever picks an adapter itself.
  """

  use Swoosh.Mailer, otp_app: :miway_credit_core
end
