defmodule MiwayCreditCore.Repo do
  use Ecto.Repo,
    otp_app: :miway_credit_core,
    adapter: Ecto.Adapters.Postgres

  @doc """
  Dynamically loads the repository configuration from the environment variables.
  This is useful for deployment where database credentials may be stored in environment variables.
  """
  def init(_, config) do
    # Optional: Dynamically construct config if needed
    # For example, url = System.get_env("DATABASE_URL")
    {:ok, config}
  end
end

