# Miway CreditCore — Pilot Test Execution Register

Test cases to be executed against the **real deployed pilot
environment**, with the real pilot organisation and real authorised
users created for that purpose (see §6 of the Pilot-Readiness
Checklist). This is not a re-run of the automated test suite (489
tests already pass in CI/dev — see the Checklist §1) — it is a manual,
witnessed execution against production-shaped infrastructure, because
that is the one thing the automated suite and the development sandbox
cannot prove.

**How to use this register:** for each row, record `Result`
(Pass/Fail/Blocked), `Evidence` (screenshot, log excerpt, or DB query
output — a claim without evidence does not close a row), `Tester`, and
`Date`. A failed row generates an entry in the Defect Register with a
matching Test ID. No row may be marked Pass on the basis of "it worked
in the dev sandbox" — the "Sandbox precedent" column exists to show
this exact behavior class was engineered and proven once already, as
context for triage if something *does* fail here, not as a substitute
for running it again against real infrastructure.

Every row references the real route/permission it exercises, confirmed
against `mix phx.routes` at the time this register was written —
update the reference if the routes ever change.

---

## A. Environment setup and access

| ID | Test Case | Expected Result | Sandbox precedent | Result | Evidence | Tester | Date |
|---|---|---|---|---|---|---|---|
| A1 | Create the real pilot organisation (`Organisations.create_organisation/1`, platform-admin only, outside the general UI) | Organisation created with its own settings, chart of accounts auto-seeded, default "Standard Loan" product auto-provisioned | Step 5, 8 | | | | |
| A2 | Bootstrap the pilot's real first platform administrator via `MiwayCreditCore.Release.create_platform_administrator/0` with real `ADMIN_EMAIL`/`ADMIN_PASSWORD` — **not** any seed script | Admin account created; seed scripts (`seeds.exs`, `add_test_accounts.exs`) confirmed to refuse under `MIX_ENV=prod` | Step 18 | | | | |
| A3 | Create real staff accounts for each pilot role (org admin, loan officer) via `Authorization.enroll_staff_member/2`, assign roles via `Authorization.assign_role/2` | Each account logs in and lands on the correct dashboard for its role | Step 4, 11 | | | | |
| A4 | Each pilot staff member enrolls real TOTP MFA (`/admin/settings/2fa`) | QR enrollment succeeds; login requires a valid 6-digit code afterward | Step 17 | | | | |
| A5 | Confirm no demo/seed accounts (`admin@example.com` etc.) exist or are reachable in the pilot environment | Login with any known demo credential fails | Step 18, post-roadmap round 1 | | | | |

## B. Core loan lifecycle (happy path, full reconciliation)

| ID | Test Case | Expected Result | Sandbox precedent | Result | Evidence | Tester | Date |
|---|---|---|---|---|---|---|---|
| B1 | Create a real customer with full KYC (individual, NRC, structured address, income) — `POST /admin/customers` | Customer created; `kyc_status: not_started` | Step 7 | | | | |
| B2 | Upload a real KYC document (a genuine, non-malicious PDF/JPEG/PNG under 10MB) — `POST /admin/customers/:id/kyc_documents` | Upload succeeds, malware-scanned, encrypted at rest, renders on the customer page | Step 7, 17, post-roadmap round 2 | | | | |
| B3 | Verify KYC — `PATCH /admin/customers/:id/kyc/verify` | `kyc_status: verified` | Step 7 | | | | |
| B4 | Submit a loan application within the product's principal/term limits — `POST /admin/loans` | Application created, `status: pending` | Step 3, 8, 9 | | | | |
| B5 | Assess the application (loan officer) — `PATCH /admin/loans/:id/assess` | `status: under_review`; `/approve` on a still-pending application is refused before this step | Step 9 | | | | |
| B6 | Approve at every configured level (org admin or higher, distinct from the assessor) — `PATCH /admin/loans/:id/approve` per level | Status advances only once the *final* required level concurs; same officer attempting a second decision is refused (`:already_decided`) | Step 6, 11 | | | | |
| B7 | Disburse — `PATCH /admin/loans/:id/disburse` | `LoanAccount` created only now (not at approval); contract reference generated; repayment schedule generated; disbursement ledger entry posted | Step 9, 12 | | | | |
| B8 | Record a full on-time repayment covering one installment — `POST /admin/loans/:id/payments` | Payment allocated Penalty → Interest → Principal (configured order); installment marked paid; ledger updated | Step 13, 14 | | | | |
| B9 | Reconcile: confirm `outstanding_balance` on the account matches the sum of unpaid schedule amounts, and the organisation's trial balance still holds (`total_debits == total_credits`) after B7–B8 | Both reconcile exactly | Step 3, 14 | | | | |
| B10 | Print/view a payment receipt — `GET /admin/loans/:id/payments/:transaction_id/receipt` | Receipt renders with correct amounts | Step 13 | | | | |
| B11 | Repay the account in full and confirm account closes correctly | Final installment clears; no outstanding balance remains | Step 13 | | | | |

## C. Conditional approval, referral, and duplicate-submission handling

| ID | Test Case | Expected Result | Sandbox precedent | Result | Evidence | Tester | Date |
|---|---|---|---|---|---|---|---|
| C1 | Conditionally approve an application — `PATCH /admin/loans/:id/conditionally_approve` | `/disburse` is blocked until conditions are cleared | Step 11 | | | | |
| C2 | Clear conditions — `PATCH /admin/loans/:id/clear_conditions`, then disburse | Disbursement proceeds normally | Step 11 | | | | |
| C3 | Refer an application for missing information — `PATCH /admin/loans/:id/refer`, then re-assess | Referral round-trips back into the normal flow; the referring officer can still approve afterward (confirmed non-regression of the referral/`:already_decided` interaction) | Step 11 | | | | |
| C4 | Submit the exact same payment form twice in immediate succession (double-click / network retry) — `POST /admin/loans/:id/payments` with the same idempotency key | Exactly one transaction and one balance debit is recorded, not two | Post-roadmap round 2 | | | | |
| C5 | Submit a genuinely new payment (fresh page load, new idempotency key) immediately after C4 | Recorded as a separate, real payment | Post-roadmap round 2 | | | | |
| C6 | Attempt approval as the same officer who created/assessed the application | Refused — maker-checker violation | Step 6, 11 | | | | |
| C7 | Attempt approval without the conflict-of-interest attestation checked | Refused until attested | Step 11 | | | | |

## D. Reversals and failure scenarios

| ID | Test Case | Expected Result | Sandbox precedent | Result | Evidence | Tester | Date |
|---|---|---|---|---|---|---|---|
| D1 | Reverse a disbursement before any repayment — `PATCH /admin/loans/:id/reverse_disbursement` | Compensating ledger entry exactly offsets the original; account/schedule effectively unwound | Step 12 | | | | |
| D2 | Attempt to reverse a disbursement **after** a posted payment exists | Refused with a specific `:payments_already_received` message | Step 12 | | | | |
| D3 | Void a posted payment — `PATCH /admin/loans/:id/payments/:transaction_id/void` | Balance and installment status restored; row retained (not deleted), ledger reversal posted | Step 13, 14 | | | | |
| D4 | Mark a payment failed after the fact (e.g. simulating a bounced cheque) — `PATCH /admin/loans/:id/payments/:transaction_id/fail` | Same reversal mechanics as void; balance/status restored | Step 13 | | | | |
| D5 | Record a failed payment attempt that never reconciled at all — `POST /admin/loans/:id/payments/failed` | Zero allocation/ledger/balance effect; logged only | Step 13 | | | | |
| D6 | Overpay an installment | Account closes; excess recorded as a traceable `overpayment_amount`, not silently absorbed or rejected | Step 13 | | | | |
| D7 | Attempt a payment on an application with no disbursed account yet (direct POST, bypassing the UI) | Friendly redirect/error, not a server crash | Step 13 (real bug found and fixed) | | | | |
| D8 | Upload a deliberately non-KYC file type (e.g. `.exe` renamed) | Rejected; no orphaned file left on disk | Step 17 | | | | |
| D9 | Upload a real EICAR test file (if ClamAV is genuinely installed on the pilot host) | Rejected as malware-positive — this is the one detection path never verified in the dev sandbox | Not previously verified — see Checklist §3.3 | | | | |
| D10 | Enter 5 wrong TOTP codes in a row on login | Account locks; the correct 6th code is also refused while locked | Step 17 | | | | |
| D11 | Attempt 11+ rapid login or password-reset requests from one IP | Rate-limited (throttles at or before the configured 10/min limit) | Step 17 | | | | |

## E. Arrears, restructuring, and write-off

| ID | Test Case | Expected Result | Sandbox precedent | Result | Evidence | Tester | Date |
|---|---|---|---|---|---|---|---|
| E1 | Let a real installment go overdue (or use a test account with a back-dated due date if the pilot allows it) | A `CollectionCase` opens automatically; a one-time penalty accrues per the product's `late_payment_penalty_percent`; arrears bucket and days-past-due render correctly | Step 13, 15 | | | | |
| E2 | Log a collections communication/follow-up activity — `POST /admin/loans/:id/collections/activities` | Activity recorded, visible in the case history | Step 15 | | | | |
| E3 | Record a promise-to-pay — `POST /admin/loans/:id/collections/promises` — then make the matching payment | Promise correctly marked kept | Step 15 | | | | |
| E4 | Record a promise-to-pay, let the date pass with no payment | Promise correctly marked broken | Step 15 | | | | |
| E5 | Submit a restructuring request — `POST /admin/loans/:id/restructuring_requests` — approve as a **different** officer than the requester | Old remaining installments marked `restructured`; a fresh schedule generated over the extended term; extra interest recognized and posted to both ledgers; org trial balance still holds | Step 15 | | | | |
| E6 | Attempt to approve a restructuring request as the same officer who requested it | Refused — maker-checker | Step 15 | | | | |
| E7 | Submit and approve a write-off request — `POST /admin/loans/:id/write_off_requests` then `.../approve` | Balance zeroed; Bad Debt Expense posts correctly; trial balance still holds afterward | Step 15, 14 | | | | |
| E8 | Set recovery status to `legal_action` — `PATCH /admin/loans/:id/collections/recovery_status` | Account status flips to `defaulted` | Step 15 | | | | |

## F. Isolation, authorization, and audit

| ID | Test Case | Expected Result | Sandbox precedent | Result | Evidence | Tester | Date |
|---|---|---|---|---|---|---|---|
| F1 | If the pilot ever has a second organisation: attempt to fetch another organisation's customer/loan by direct URL id | Real 404, not a leak of existence | Step 5 (`cross_organisation_isolation_test.exs`) | | | | |
| F2 | A loan officer attempts an org-admin-only action (e.g. approve above their authority limit, manage products) | Real 403 from the server, not just a hidden UI element | Step 6, 8 | | | | |
| F3 | An organisation administrator attempts to view `/admin/system-health` | Real 403 — platform-admin only | Runbook §11 | | | | |
| F4 | Review `/admin/audit-logs` for a completed pilot transaction | The actor, organisation, and event are all correctly recorded — confirm `actor_id` is populated, not `nil` (a real historical bug, fixed Step 16) | Step 16 | | | | |
| F5 | Export the audit log CSV | Contains only events for the requesting organisation | Step 16 | | | | |

## G. Operational readiness (run against the real deployed environment)

| ID | Test Case | Expected Result | Sandbox precedent | Result | Evidence | Tester | Date |
|---|---|---|---|---|---|---|---|
| G1 | `curl -i https://<host>/up` | `200`, `{"status":"ok"}` | Step 18 | | | | |
| G2 | `curl -i https://<host>/ready` | `200`, `{"status":"ready"}` (or `503` if Postgres is deliberately taken down, to confirm the failure path) | Runbook §11 | | | | |
| G3 | Run a real backup — `mix miway_credit_core.backup` (or the release equivalent) | Produces `db.dump`, `kyc.tar.gz`, `manifest.json`, `SHA256SUMS`; `sha256sum -c SHA256SUMS` passes | Runbook §10 | | | | |
| G4 | Run a real restore drill against that backup — `mix miway_credit_core.restore_drill` | `overall_status: "ok"`; no scratch DB/directory left behind afterward | Runbook §10 | | | | |
| G5 | `mix miway_credit_core.verify_kyc_key` / `verify_mfa_key` against the real deployed keys | Both report success against real stored data | Runbook §9a, §10 | | | | |
| G6 | Trigger a real password-reset email to an inbox you control | Email arrives (check spam), link works end-to-end | Runbook §12 | | | | |
| G7 | Confirm `/admin/system-health` shows both schedulers (`ArrearsScheduler`, `KycRetentionScheduler`, `BackupScheduler`) with a recent, non-stale heartbeat | All green/OK | Runbook §11 | | | | |

---

**Sign-off condition:** every row above must reach `Result = Pass` (or a documented, accepted `Blocked` with a stated reason) before the Pilot Acceptance Form may be signed. Any `Fail` generates a Defect Register entry with the same Test ID.
