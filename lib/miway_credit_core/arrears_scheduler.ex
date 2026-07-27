defmodule MiwayCreditCore.ArrearsScheduler do
  @moduledoc """
  Periodically flips unpaid installments past their due_date to
  "overdue" (MiwayCreditCore.Lending.mark_overdue_installments/0). Runs once
  shortly after startup, then on a fixed interval — no external job
  library needed at this scale.

  Disabled in the test environment (config :miway_credit_core,
  ArrearsScheduler, enabled: false) — a background process querying
  the DB outside a test's checked-out sandbox connection would error
  intermittently; the underlying query is unit-tested directly instead.
  """

  use GenServer
  require Logger

  @default_interval_ms :timer.hours(1)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Process.send_after(self(), :check_overdue, :timer.seconds(10))
    {:ok, %{interval_ms: interval_ms()}}
  end

  @impl true
  def handle_info(:check_overdue, state) do
    count = MiwayCreditCore.Lending.mark_overdue_installments()

    if count > 0 do
      Logger.info("ArrearsScheduler: flipped #{count} installment(s) to overdue")
    end

    Process.send_after(self(), :check_overdue, state.interval_ms)
    {:noreply, state}
  end

  defp interval_ms do
    Application.get_env(:miway_credit_core, __MODULE__, [])
    |> Keyword.get(:interval_ms, @default_interval_ms)
  end
end
