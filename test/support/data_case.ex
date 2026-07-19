defmodule LoanSystem.DataCase do
  @moduledoc """
  Sets up an isolated, transactional Ecto sandbox connection for each test
  in this case template. Use for context/schema tests that hit the DB.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias LoanSystem.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import LoanSystem.DataCase
    end
  end

  setup tags do
    LoanSystem.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Checks out a sandbox connection for the test, wrapped in a transaction
  that's rolled back at the end — no manual cleanup needed between tests.
  """
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(LoanSystem.Repo, shared: not tags[:async])
    ExUnit.Callbacks.on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  @doc "Extracts changeset errors into a map of field => [message, ...]."
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
