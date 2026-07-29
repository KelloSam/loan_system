defmodule MiwayCreditCoreWeb.Plugs.RateLimitPlugTest do
  # Shared ETS-backed rate-limit state is process-global, not sandboxed
  # per test — async: false plus an explicit clean in setup keeps this
  # deterministic (ExUnit runs non-async modules only after every async
  # module has finished, so no other test can be mid-flight against the
  # same throttle bucket while this one runs).
  use MiwayCreditCoreWeb.ConnCase, async: false

  import MiwayCreditCore.AccountsFixtures

  alias MiwayCreditCore.Accounts

  @password "CorrectHorse123"

  setup do
    PlugAttack.Storage.Ets.clean(MiwayCreditCoreWeb.RateLimitStorage)
    :ok
  end

  test "an 11th POST to /login/verify within a minute is throttled", %{conn: conn} do
    user = staff_member_fixture("loan_officer", %{password: @password})
    secret = Accounts.generate_totp_secret()
    {:ok, user} = Accounts.enable_totp(user, secret)

    attempt = fn ->
      conn
      |> Plug.Conn.put_session(:pending_2fa_user_id, user.id)
      |> then(&post(&1, ~p"/login/verify", totp: %{code: "000000"}))
    end

    responses = for _ <- 1..10, do: attempt.()
    assert Enum.all?(responses, &(&1.status == 200))
    assert List.last(responses) |> Plug.Conn.get_resp_header("x-ratelimit-remaining") == ["0"]

    blocked = attempt.()
    assert redirected_to(blocked) == ~p"/login/verify"
    assert Phoenix.Flash.get(blocked.assigns.flash, :error) =~ "Too many attempts"
  end
end
