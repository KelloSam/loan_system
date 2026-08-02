# Miway CreditCore — Pilot-Readiness Checklist

Status document for the first controlled pilot. It separates four
different kinds of statement, because conflating them is exactly how a
system ends up looking "done" when it is really "done pending a
decision nobody made yet":

1. **Application engineering** — code, tested, demoed live against a
   real database, already committed. Nothing here is aspirational.
2. **Deployment configuration** — infrastructure and settings that
   exist as working *mechanisms* in the codebase but have never been
   pointed at real production infrastructure, because no such
   infrastructure exists in this development sandbox.
3. **Evidence required before launch** — checks that must be
   performed against real infrastructure once it exists, not
   substitutable by anything already done here.
4. **Deliberately out of scope for this pilot** — named so nobody
   mistakes silence for an oversight.

Every claim below is traceable to a specific commit, test count, or
section of `docs/MIWAY_CREDITCORE_DEPLOYMENT_RUNBOOK.md` ("the
Runbook"). Where this document says "closed," it means closed at the
application-engineering layer specifically — see the deployment
column before treating anything as pilot-ready end to end.

---

## 1. Application engineering — completed

| Area | What was built | Evidence |
|---|---|---|
| Loan lifecycle | Application → assessment → multi-level/committee approval → conditional approval/referral → disbursement → repayment → collections → write-off, as a real state machine, not a flat status field | Steps 9, 11 |
| Multi-tenancy & isolation | Every context call takes a `Scope`; cross-organisation access returns 404, never a leak | `cross_organisation_isolation_test.exs`, Step 5 |
| Roles & authorization | Server-side permission checks on every admin action (`RequirePermissionPlug`), maker-checker enforced at the context layer, per-role approval limits | Step 6 |
| Products & affordability | Configurable loan products, debt-to-income affordability check, CRB (credit bureau) check gate | Steps 8, 10 |
| Accounting | Per-account subledger (`AccountingEntry`) plus a real double-entry general ledger (chart of accounts, journal entries), trial balance verifiably holds | Step 14 |
| Collections & arrears | Arrears buckets, collection cases, promise-to-pay tracking, restructuring, write-off — all with maker-checker | Step 15 |
| Audit trail | Every action logged with a real actor id and organisation scope (a real bug — actor was silently never recorded — found and fixed in Step 16) | Step 16 |
| KYC | Structured customer identity, document upload with type/size whitelist, malware scanning (fail-closed), AES-256-GCM encryption at rest, retention/purge policy | Steps 7, 17, post-roadmap round 2 |
| MFA (TOTP) | Login 2FA with brute-force protection (rate limit + account lockout); secrets encrypted at rest, AES-256-GCM, migrated from legacy plaintext-Base64 with no forced re-enrollment | Step 17, 2026-08-02 session |
| Idempotency | Duplicate-submission protection on payment recording (unique key per form render) | Post-roadmap round 2 |
| Application-health visibility | `/up`, `/ready`, scheduler heartbeats, DB pool queue-time tracking, scanner-failure counter, structured error capture, all on `/admin/system-health` (platform-admin only) | Runbook §11 |
| Backup & restore mechanism | Automated daily backup (DB + KYC files + checksummed manifest), a real restore-drill command verified against scratch resources | Runbook §10 |
| Automated test suite | **489 tests, 0 failures**, full suite green, `mix format --check-formatted` clean, `mix compile --warnings-as-errors` clean | 2026-08-02 session |

**Not built, and explicitly out of scope for this pilot** (stated once here, not repeated per row above): AI features, native mobile apps, multiple live CRB provider integrations (one manual adapter only), automated credit scoring beyond the built debt-to-income check, biometric verification, automated payroll integration, investor/securitisation functions, and the renewable 12-month customer licensing module (see §4 below).

---

## 2. Deployment configuration — required, not yet done

Nothing in this section is a code defect. Each row is a real mechanism that exists and has been tested against its own logic, but has never been pointed at real external infrastructure because none exists in this sandbox.

| Item | Mechanism status | What launch requires | Runbook ref |
|---|---|---|---|
| Production database | SSL config fixed and correct against OTP's bundled CA store | A real managed Postgres instance (or equivalent), `DATABASE_URL` set, connection confirmed | §2 |
| KYC document storage | `DocumentStorage` writes encrypted files to a configurable path; release refuses to boot without `KYC_UPLOAD_DIR` set | A real persistent volume outside the release directory, on a **single** app instance (local-disk storage does not support multi-instance deployment today) | §9 |
| KYC/MFA encryption keys | AES-256-GCM encryption built and live-verified for both KYC files and TOTP secrets | `KYC_ENCRYPTION_KEY` and `MFA_ENCRYPTION_KEY` generated (32 random bytes each, must differ), stored in a real secrets vault, never alongside backups | §9, §9a |
| Malware scanning | `MalwareScanner.Local` fails closed by design; correctly rejects uploads when ClamAV is absent (verified in this sandbox) | ClamAV installed and signature-updating on the real host; real-virus detection path (e.g. EICAR test file) has **not** been verified anywhere, since ClamAV isn't installed here | §8 |
| SMTP / password-reset email | Deliberately optional at boot; fails closed and logs server-side when unconfigured; real SMTP wire protocol confirmed against a local debug server | A real provider account (SendGrid, Mailgun, Postmark, SES, etc.), verified sending domain, and a live delivery test to a real inbox — none of this exists in this sandbox | §12 |
| Off-site backup destination | `Backup.Destination.Local` is the only adapter built; automated daily run + restore drill both verified against the real dev database | A real off-site destination (S3 or equivalent) — today backups live on the same host as the database they protect, which is not survivable disaster recovery | §10 |
| Backup encryption at rest | KYC files are already ciphertext before backup touches them; the Postgres dump itself is not separately encrypted | Encrypted disk/bucket at the destination layer, or an encrypting `Destination` adapter | §10 |
| External alerting | Application exposes health/failure data (`/admin/system-health`, structured `[error_reporter]` log lines); nothing pages a human | A real alerting product (PagerDuty, Opsgenie, a Slack webhook, uptime monitor on `/up`, orchestrator readiness probe on `/ready`) | §11 |
| Host/infrastructure monitoring | Out of this application's process boundary by construction — cannot be built here | Disk space, CPU, and health monitoring on the Postgres host and app host themselves | §11 |
| Isolated pilot environment | N/A | A real deployment target (VM/container/managed platform), separate from this development sandbox | — |

---

## 3. Evidence required before pilot launch

These are one-time verification steps against **real** infrastructure — none can be satisfied by re-reading this document or by the sandbox testing already done.

1. Confirm SSL handshake against the real managed Postgres instance (§2).
2. `ADMIN_EMAIL`/`ADMIN_PASSWORD` bootstrap of the real first platform administrator via `MiwayCreditCore.Release.create_platform_administrator/0` — **never** the demo seed scripts, which refuse to run under `MIX_ENV=prod` by design (§5).
3. `clamscan --version` and an EICAR-file upload test against the real ClamAV install — confirms actual detection, not just fail-closed-when-absent (§8).
4. A real KYC document upload → download round trip on the deployed environment, confirming encryption/decryption works against the real `KYC_ENCRYPTION_KEY`.
5. A real password-reset email delivered to an inbox you control, including checking spam/junk on a fresh sending domain, and the reset link confirmed working end-to-end (§12).
6. A real `mix miway_credit_core.backup` run against the deployed environment, followed by a real `restore_drill`, confirming `overall_status: "ok"` (§10) — the dev-sandbox drill evidence in the Runbook does not substitute for this.
7. `mix miway_credit_core.verify_kyc_key` and `verify_mfa_key` run against the deployed environment's real configured keys.
8. A human, out-of-band retrieval of the vaulted copy of `KYC_ENCRYPTION_KEY`/`MFA_ENCRYPTION_KEY`, confirming that specific copy decrypts a real record — the only genuine disaster-recovery test of the backup itself, distinct from item 7 above (§9a, §10).
9. `curl -i https://<host>/up` and `/ready` from outside the deployment network, and confirmation that a real uptime monitor / orchestrator readiness probe is actually pointed at them.
10. A fingerprint match check: the sha256 fingerprint recorded against the vaulted key matches the fingerprint a fresh backup manifest reports (§10).

---

## 4. Deliberately out of scope for this pilot

- **The renewable 12-month customer licensing module** (organisation-level `licence_status`/expiry/grace-period enforcement). Commercially important, deliberately designed and built separately so it doesn't distract from proving the first controlled pilot. A time-limited pilot entitlement is to be administered manually by Miway under the signed pilot agreement in the interim.
- Multi-instance/horizontal scaling — `DocumentStorage` (local disk) and `Monitoring.Store` (single-instance ETS) both assume one app instance; scaling out requires object storage and a cross-instance aggregation story neither exists today.
- Key rotation (KYC or MFA) — the version-metadata scaffolding exists (`totp_secret_version`), but the re-encryption migration itself is not built.
- Hostname verification on the Postgres TLS connection (chain trust is verified; hostname-to-cert matching is not) — flagged, not built (§2).

---

## 5. Sign-off gate

This checklist is not itself the acceptance record. It feeds three companion documents:

- `MIWAY_CREDITCORE_PILOT_TEST_EXECUTION_REGISTER.md` — the specific test cases to run once the deployed environment is live.
- `MIWAY_CREDITCORE_PILOT_DEFECT_REGISTER.md` — where anything found during that testing gets logged and tracked to resolution.
- `MIWAY_CREDITCORE_PILOT_ACCEPTANCE_FORM.md` — the formal sign-off, which may only be signed once every §2 item is configured, every §3 item has real evidence attached, and the Defect Register has no open item above the agreed severity threshold.
