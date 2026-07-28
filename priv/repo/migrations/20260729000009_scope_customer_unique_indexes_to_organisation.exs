defmodule MiwayCreditCore.Repo.Migrations.ScopeCustomerUniqueIndexesToOrganisation do
  @moduledoc """
  Fixes a real gap left over from the Step 3 clients→customers rename:
  `customers_phone_index` etc. were global unique indexes, so two
  different organisations on this platform could never both have a
  customer with the same phone/NRC/email — contradicting Step 5's
  whole premise that each organisation manages its own customer
  roster. Each identity field is now unique per organisation, not
  platform-wide.
  """

  use Ecto.Migration

  def change do
    drop unique_index(:customers, [:phone], name: :customers_phone_index)
    drop unique_index(:customers, [:id_number], name: :customers_id_number_index)
    drop unique_index(:customers, [:email], name: :customers_email_index)

    create unique_index(:customers, [:organisation_id, :phone])
    create unique_index(:customers, [:organisation_id, :id_number])
    create unique_index(:customers, [:organisation_id, :email])
  end
end
