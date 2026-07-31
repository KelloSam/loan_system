defmodule MiwayCreditCore.Backup.RepoConfigTest do
  use ExUnit.Case, async: true

  alias MiwayCreditCore.Backup.RepoConfig

  describe "connection_params/0" do
    test "returns the real, currently configured Repo connection params" do
      assert %{hostname: "localhost", port: 5433, username: "think"} =
               RepoConfig.connection_params()
    end
  end

  describe "from_config/1" do
    test "handles the discrete-key shape (dev/test)" do
      config = %{hostname: "db.internal", port: 5432, username: "u", password: "p", database: "d"}
      assert RepoConfig.from_config(config) == config
    end

    test "handles the single :url shape (prod)" do
      assert RepoConfig.from_config(%{url: "ecto://u:p@db.internal:5432/d"}) == %{
               hostname: "db.internal",
               port: 5432,
               username: "u",
               password: "p",
               database: "d"
             }
    end
  end

  describe "parse_database_url/1" do
    test "parses host, port, username, password, database" do
      assert RepoConfig.parse_database_url("ecto://myuser:mypass@myhost:6543/mydb") == %{
               hostname: "myhost",
               port: 6543,
               username: "myuser",
               password: "mypass",
               database: "mydb"
             }
    end

    test "defaults to port 5432 when absent" do
      assert %{port: 5432} = RepoConfig.parse_database_url("ecto://u:p@host/db")
    end

    test "URL-decodes username and password" do
      assert %{username: "us er", password: "p@ss"} =
               RepoConfig.parse_database_url("ecto://us%20er:p%40ss@host:5432/db")
    end
  end
end
