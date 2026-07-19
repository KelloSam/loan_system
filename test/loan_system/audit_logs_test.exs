defmodule LoanSystem.AuditLogsTest do
  use LoanSystem.DataCase, async: true

  alias LoanSystem.AuditLogs

  describe "log/2" do
    test "always returns :ok and persists the event" do
      assert :ok =
               AuditLogs.log("loan_approved",
                 actor_id: Ecto.UUID.generate(),
                 actor_email: "admin@example.com",
                 target_type: "loan",
                 target_id: Ecto.UUID.generate(),
                 metadata: %{amount: "1000.00"},
                 ip_address: "127.0.0.1"
               )

      [entry] = AuditLogs.list_recent()
      assert entry.event == "loan_approved"
      assert entry.actor_email == "admin@example.com"
      assert entry.target_type == "loan"
      assert entry.metadata == %{"amount" => "1000.00"}
    end

    test "accepts an atom event name and stringifies it" do
      :ok = AuditLogs.log(:client_created)
      [entry] = AuditLogs.list_recent()
      assert entry.event == "client_created"
    end

    test "stringifies a non-binary target_id" do
      :ok = AuditLogs.log("event", target_id: 42)
      [entry] = AuditLogs.list_recent()
      assert entry.target_id == "42"
    end
  end

  describe "list_recent/1" do
    test "returns events newest first, respecting the limit" do
      AuditLogs.log("first")
      AuditLogs.log("second")
      AuditLogs.log("third")

      [newest, middle] = AuditLogs.list_recent(2)
      assert newest.event == "third"
      assert middle.event == "second"
    end
  end

  describe "count_today/0" do
    test "counts only events logged today" do
      assert AuditLogs.count_today() == 0
      AuditLogs.log("a")
      AuditLogs.log("b")
      assert AuditLogs.count_today() == 2
    end
  end
end
