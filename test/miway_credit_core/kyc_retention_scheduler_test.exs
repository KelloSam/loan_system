defmodule MiwayCreditCore.KycRetentionSchedulerTest do
  # Same technique as ArrearsSchedulerTest — calls handle_info/2
  # directly rather than starting the (test-disabled) GenServer.
  use MiwayCreditCore.DataCase, async: false

  alias MiwayCreditCore.KycRetentionScheduler
  alias MiwayCreditCore.Monitoring
  alias MiwayCreditCore.Monitoring.Store

  setup do
    Store.reset!()
    :ok
  end

  test "a successful tick records a heartbeat and reschedules itself" do
    assert Monitoring.last_tick(:kyc_retention_scheduler) == :never

    assert {:noreply, %{interval_ms: 999_999_999}} =
             KycRetentionScheduler.handle_info(:purge_expired_kyc_documents, %{
               interval_ms: 999_999_999
             })

    assert {:ok, %DateTime{}} = Monitoring.last_tick(:kyc_retention_scheduler)
  end
end
