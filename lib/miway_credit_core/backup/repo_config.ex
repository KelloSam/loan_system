defmodule MiwayCreditCore.Backup.RepoConfig do
  @moduledoc """
  Pure conversion from `MiwayCreditCore.Repo`'s live config to plain
  connection params `pg_dump`/`pg_restore`/`psql` need. Handles both
  shapes this app's Repo config actually takes: dev/test's discrete
  `hostname`/`port`/`username`/`password`/`database` keys, and prod's
  single `DATABASE_URL` (`ecto://user:pass@host:port/database`).
  """

  @doc "Connection params for the app's real, currently configured Repo."
  def connection_params do
    MiwayCreditCore.Repo.config() |> Map.new() |> from_config()
  end

  @doc false
  def from_config(%{url: url}) when is_binary(url), do: parse_database_url(url)

  def from_config(%{
        hostname: hostname,
        port: port,
        username: username,
        password: password,
        database: database
      }) do
    %{hostname: hostname, port: port, username: username, password: password, database: database}
  end

  @doc "Parses an ecto://user:pass@host:port/database URL into connection params."
  def parse_database_url(url) do
    uri = URI.parse(url)
    [username, password] = String.split(uri.userinfo || "", ":", parts: 2)

    %{
      hostname: uri.host,
      port: uri.port || 5432,
      username: URI.decode(username),
      password: URI.decode(password),
      database: String.trim_leading(uri.path || "", "/")
    }
  end
end
