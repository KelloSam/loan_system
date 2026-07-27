defmodule MiwayCreditCoreWeb.ConnCase do
  @moduledoc """
  Sets up a connection for controller/plug tests, plus the same
  transactional Ecto sandbox DataCase uses.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.Controller, only: [fetch_flash: 2]
      import Phoenix.ConnTest
      import MiwayCreditCoreWeb.ConnCase
      use MiwayCreditCoreWeb, :verified_routes

      @endpoint MiwayCreditCoreWeb.Endpoint
    end
  end

  setup tags do
    MiwayCreditCore.DataCase.setup_sandbox(tags)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Test.init_test_session(%{})
      |> Phoenix.Controller.fetch_flash([])

    {:ok, conn: conn}
  end
end
