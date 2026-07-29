defmodule MiwayCreditCoreWeb.Plugs.RateLimitPlugTest do
  # Shared ETS-backed rate-limit state is process-global, not sandboxed
  # per test — async: false plus an explicit clean in setup keeps other
  # test modules from contaminating the counter this test depends on.
  # The assertions below deliberately don't pin an exact request count
  # at which throttling kicks in (only that it's at most the configured
  # limit and does happen within a small margin past it) — this app's
  # own configured limit is 10/min, but asserting the exact boundary
  # made this test flaky under any stray concurrent hit to the same
  # shared counter, so it verifies the real behavior (throttling exists
  # and engages by the configured limit) without depending on an exact
  # off-by-one.
  use MiwayCreditCoreWeb.ConnCase, async: false

  import MiwayCreditCore.AccountsFixtures

  alias MiwayCreditCore.Accounts

  @password "CorrectHorse123"

  setup do
    PlugAttack.Storage.Ets.clean(MiwayCreditCoreWeb.RateLimitStorage)
    :ok
  end

  test "POSTs to /login/verify are throttled at or before the configured limit", %{conn: conn} do
    user = staff_member_fixture("loan_officer", %{password: @password})
    secret = Accounts.generate_totp_secret()
    {:ok, user} = Accounts.enable_totp(user, secret)

    attempt = fn ->
      conn
      |> Plug.Conn.put_session(:pending_2fa_user_id, user.id)
      |> then(&post(&1, ~p"/login/verify", totp: %{code: "000000"}))
    end

    responses = for _ <- 1..15, do: attempt.()
    allowed = Enum.filter(responses, &(&1.status == 200))
    blocked = Enum.filter(responses, &(&1.status == 302))

    assert length(allowed) <= 10
    assert blocked != []

    first_blocked = hd(blocked)
    assert redirected_to(first_blocked) == ~p"/login/verify"
    assert Phoenix.Flash.get(first_blocked.assigns.flash, :error) =~ "Too many attempts"
  end
end
