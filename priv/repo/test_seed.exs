alias LoanSystem.{Repo, Clients, Loans}
alias LoanSystem.Clients.Client
alias LoanSystem.Loans.{Loan, Payment}

today = Date.utc_today()

clients_data = [
  %{name: "Alice Banda",   phone: "260971234567", id_number: "100100/10/1", email: "client@example.com",    address: "Plot 5, Cairo Road, Lusaka", active: true},
  %{name: "John Mwale",    phone: "260977654321", id_number: "200200/20/2", email: "john.mwale@gmail.com",   address: "House 12, Emmasdale, Lusaka", active: true},
  %{name: "Grace Phiri",   phone: "260965432109", id_number: "300300/30/3", email: "grace.phiri@gmail.com",  address: "Flat 3, Kabwata, Lusaka", active: true},
  %{name: "Peter Zulu",    phone: "260953210987", id_number: "400400/40/4", email: nil, address: "Ndola", active: false},
]

clients = Enum.map(clients_data, fn attrs ->
  case Clients.get_client_by_id_number(attrs.id_number) do
    nil ->
      {:ok, c} = Clients.create_client(attrs)
      IO.puts("Created client: #{c.name}")
      c
    existing ->
      IO.puts("Client already exists: #{existing.name}")
      existing
  end
end)

[alice, john, grace, _peter] = clients

now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

loans_data = [
  %{client_id: alice.id, amount: Decimal.new("5000.00"), interest_rate: Decimal.new("18.00"),
    term_months: 12, status: "approved",   remaining_balance: Decimal.new("4000.00"),
    purpose: "Home renovation", next_payment_date: Date.add(today, 15), approved_at: now},
  %{client_id: alice.id, amount: Decimal.new("2000.00"), interest_rate: Decimal.new("15.00"),
    term_months: 6,  status: "completed",  remaining_balance: Decimal.new("0.00"),
    purpose: "Medical expenses"},
  %{client_id: john.id,  amount: Decimal.new("10000.00"), interest_rate: Decimal.new("20.00"),
    term_months: 24, status: "pending",    remaining_balance: Decimal.new("10000.00"),
    purpose: "Business capital"},
  %{client_id: john.id,  amount: Decimal.new("3000.00"), interest_rate: Decimal.new("18.00"),
    term_months: 12, status: "approved",   remaining_balance: Decimal.new("1200.00"),
    purpose: "School fees", next_payment_date: Date.add(today, 7), approved_at: now},
  %{client_id: grace.id, amount: Decimal.new("7500.00"), interest_rate: Decimal.new("22.00"),
    term_months: 18, status: "rejected",   remaining_balance: Decimal.new("0.00"),
    purpose: "Land purchase"},
]

created_loans = Enum.map(loans_data, fn attrs ->
  {:ok, loan} = Repo.insert(Loan.changeset(%Loan{}, attrs))
  IO.puts("Created #{loan.status} loan: ZMW #{loan.amount}")
  loan
end)

import Ecto.Query

# Recalculate client stats
Enum.each([alice.id, john.id, grace.id], fn client_id ->
  balance =
    from(l in Loan,
      where: l.client_id == ^client_id and l.status in ["pending", "approved"],
      select: sum(l.remaining_balance))
    |> Repo.one()
    |> then(fn nil -> Decimal.new("0.00"); val -> val end)
  count = from(l in Loan, where: l.client_id == ^client_id, select: count(l.id)) |> Repo.one()
  from(c in Client, where: c.id == ^client_id)
  |> Repo.update_all(set: [current_balance: balance, total_loans: count])
end)

# Add payments to Alice's approved loan
alice_approved = Enum.find(created_loans, &(&1.client_id == alice.id && &1.status == "approved"))
if alice_approved do
  Repo.insert!(%Payment{loan_id: alice_approved.id, amount: Decimal.new("500.00"),
    payment_date: Date.add(today, -30), due_date: Date.add(today, -30), status: "paid"})
  Repo.insert!(%Payment{loan_id: alice_approved.id, amount: Decimal.new("500.00"),
    payment_date: Date.add(today, -15), due_date: Date.add(today, -15), status: "paid"})
  IO.puts("Added 2 payments to Alice's loan")
end

IO.puts("\n✓ Seeding complete!")
