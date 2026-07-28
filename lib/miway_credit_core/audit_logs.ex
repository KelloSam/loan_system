defmodule MiwayCreditCore.AuditLogs do
  import Ecto.Query
  alias MiwayCreditCore.Repo
  alias MiwayCreditCore.AuditLogs.AuditLog

  @doc """
  Writes an audit event. Always returns :ok — a failed write never crashes
  the calling request, so the main business flow is never blocked by logging.

  Options:
    - actor_id:    id of the Accounts.User who performed the action (integer)
    - actor_email: email of that user (stored so logs remain readable even
                   if the user record is later deleted)
    - target_type: "loan", "customer", "payment", etc.
    - target_id:   ID of the affected record
    - metadata:    map of extra context (amounts, names, etc.)
    - ip_address:  request IP as a string
  """
  def log(event, opts \\ []) do
    attrs = %{
      event: to_string(event),
      actor_id: opts[:actor_id],
      actor_email: opts[:actor_email],
      target_type: opts[:target_type],
      target_id: opts[:target_id] && to_string(opts[:target_id]),
      metadata: opts[:metadata] || %{},
      ip_address: opts[:ip_address]
    }

    %AuditLog{}
    |> AuditLog.changeset(attrs)
    |> Repo.insert()

    :ok
  end

  @doc "Returns the most recent audit events, newest first."
  def list_recent(limit \\ 100) do
    AuditLog
    |> order_by([l], desc: l.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Count of audit events recorded today."
  def count_today do
    start_of_day = NaiveDateTime.new!(Date.utc_today(), ~T[00:00:00])

    from(l in AuditLog, where: l.inserted_at >= ^start_of_day, select: count(l.id))
    |> Repo.one()
  end
end
