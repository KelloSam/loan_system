defmodule MiwayCreditCore.CreditReporting do
  @moduledoc """
  Reserved context boundary. Will own the internal abstraction over
  credit reference bureau (CRB) reporting — consent, enquiries,
  report history, and provider adapters — so other contexts ask
  CreditReporting for a report instead of calling a CRB provider
  directly.

  No schema, migration, or function exists yet. Implementation is
  Step 10. See `docs/architecture/context_boundaries.md` for
  ownership, dependencies, and what this context must never do.
  """
end
