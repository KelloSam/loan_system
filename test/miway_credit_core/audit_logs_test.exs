defmodule MiwayCreditCore.AuditLogsTest do
  use MiwayCreditCore.DataCase, async: true

  import MiwayCreditCore.OrganisationsFixtures

  alias MiwayCreditCore.AuditLogs
  alias MiwayCreditCore.Accounts.Scope

  describe "log/2" do
    test "always returns :ok and persists the event" do
      assert :ok =
               AuditLogs.log("loan_approved",
                 actor_id: 1,
                 actor_email: "admin@example.com",
                 target_type: "loan",
                 target_id: Ecto.UUID.generate(),
                 metadata: %{amount: "1000.00"},
                 ip_address: "127.0.0.1"
               )

      organisation = organisation_fixture()
      :ok = AuditLogs.log("org_event", organisation_id: organisation.id)
      [entry] = AuditLogs.list_recent(%Scope{organisation_id: organisation.id})
      assert entry.event == "org_event"
    end

    test "accepts an atom event name and stringifies it" do
      organisation = organisation_fixture()
      :ok = AuditLogs.log(:customer_created, organisation_id: organisation.id)
      [entry] = AuditLogs.list_recent(%Scope{organisation_id: organisation.id})
      assert entry.event == "customer_created"
    end

    test "stringifies a non-binary target_id" do
      organisation = organisation_fixture()
      :ok = AuditLogs.log("event", target_id: 42, organisation_id: organisation.id)
      [entry] = AuditLogs.list_recent(%Scope{organisation_id: organisation.id})
      assert entry.target_id == "42"
    end

    test "organisation_id defaults to nil for a genuinely pre-auth event" do
      :ok = AuditLogs.log("login_failure", actor_email: "nobody@example.com")
      [entry] = AuditLogs.list_recent(%Scope{organisation_id: :all}, 1)
      assert entry.organisation_id == nil
    end
  end

  describe "list_recent/2 — organisation scoping" do
    test "an organisation's scope only ever sees its own events, never another organisation's or a null-org platform event" do
      org_a = organisation_fixture()
      org_b = organisation_fixture()

      :ok = AuditLogs.log("a_event", organisation_id: org_a.id)
      :ok = AuditLogs.log("b_event", organisation_id: org_b.id)
      :ok = AuditLogs.log("platform_event", organisation_id: nil)

      scope_a = %Scope{organisation_id: org_a.id}
      events_a = AuditLogs.list_recent(scope_a) |> Enum.map(& &1.event)

      assert "a_event" in events_a
      refute "b_event" in events_a
      refute "platform_event" in events_a
    end

    test "a platform administrator's :all scope sees every organisation's events, including null-org ones" do
      org_a = organisation_fixture()
      org_b = organisation_fixture()

      :ok = AuditLogs.log("a_event", organisation_id: org_a.id)
      :ok = AuditLogs.log("b_event", organisation_id: org_b.id)
      :ok = AuditLogs.log("platform_event", organisation_id: nil)

      events = AuditLogs.list_recent(%Scope{organisation_id: :all}) |> Enum.map(& &1.event)

      assert "a_event" in events
      assert "b_event" in events
      assert "platform_event" in events
    end

    test "respects the limit, newest first" do
      organisation = organisation_fixture()
      scope = %Scope{organisation_id: organisation.id}

      AuditLogs.log("first", organisation_id: organisation.id)
      AuditLogs.log("second", organisation_id: organisation.id)
      AuditLogs.log("third", organisation_id: organisation.id)

      [newest, middle] = AuditLogs.list_recent(scope, 2)
      assert newest.event == "third"
      assert middle.event == "second"
    end
  end

  describe "list_filtered/3" do
    setup do
      organisation = organisation_fixture()
      %{organisation: organisation, scope: %Scope{organisation_id: organisation.id}}
    end

    test "filters by event", %{organisation: organisation, scope: scope} do
      AuditLogs.log("loan_application_created", organisation_id: organisation.id)
      AuditLogs.log("customer_created", organisation_id: organisation.id)

      results = AuditLogs.list_filtered(scope, %{"event" => "customer_created"})
      assert Enum.map(results, & &1.event) == ["customer_created"]
    end

    test "filters by partial actor_email", %{organisation: organisation, scope: scope} do
      AuditLogs.log("event_1", actor_email: "alice@example.com", organisation_id: organisation.id)
      AuditLogs.log("event_2", actor_email: "bob@example.com", organisation_id: organisation.id)

      results = AuditLogs.list_filtered(scope, %{"actor_email" => "alice"})
      assert Enum.map(results, & &1.event) == ["event_1"]
    end

    test "filters by date range", %{organisation: organisation, scope: scope} do
      AuditLogs.log("in_range", organisation_id: organisation.id)

      today = Date.utc_today() |> Date.to_iso8601()
      tomorrow = Date.utc_today() |> Date.add(1) |> Date.to_iso8601()
      yesterday = Date.utc_today() |> Date.add(-1) |> Date.to_iso8601()

      assert Enum.any?(AuditLogs.list_filtered(scope, %{"from" => today, "to" => tomorrow}), &(&1.event == "in_range"))
      refute Enum.any?(AuditLogs.list_filtered(scope, %{"from" => yesterday, "to" => yesterday}), &(&1.event == "in_range"))
    end

    test "never returns another organisation's events even with a matching filter", %{organisation: organisation, scope: scope} do
      other_organisation = organisation_fixture()
      AuditLogs.log("shared_event_name", organisation_id: other_organisation.id)

      assert AuditLogs.list_filtered(scope, %{"event" => "shared_event_name"}) == []
    end
  end

  describe "audit_csv/2" do
    test "produces a header row plus one row per event, scoped to the organisation" do
      organisation = organisation_fixture()
      other_organisation = organisation_fixture()
      scope = %Scope{organisation_id: organisation.id}

      AuditLogs.log("loan_application_created", actor_email: "staff@example.com", organisation_id: organisation.id)
      AuditLogs.log("other_org_event", organisation_id: other_organisation.id)

      csv = AuditLogs.audit_csv(scope)
      lines = String.split(csv, "\r\n", trim: true)

      assert hd(lines) == "time,event,actor,target_type,target_id,ip_address"
      assert Enum.any?(lines, &(&1 =~ "loan_application_created"))
      refute Enum.any?(lines, &(&1 =~ "other_org_event"))
    end
  end

  describe "count_today/1" do
    test "counts only today's events, scoped to the organisation" do
      organisation = organisation_fixture()
      scope = %Scope{organisation_id: organisation.id}

      assert AuditLogs.count_today(scope) == 0
      AuditLogs.log("a", organisation_id: organisation.id)
      AuditLogs.log("b", organisation_id: organisation.id)
      assert AuditLogs.count_today(scope) == 2
    end
  end
end
