# Miway CreditCore — Pilot Defect Register

Live log of defects found during pilot deployment configuration and
Test Execution Register runs. This document starts empty of real
defects by design — no pilot execution has occurred yet as of this
writing (2026-08-02). Do not pre-populate it with guessed or
hypothetical issues; only log something here once it has actually been
observed against real deployed infrastructure or real pilot testing.

## Severity scale

| Severity | Definition | Sign-off impact |
|---|---|---|
| **Critical** | Data loss, financial-ledger imbalance, a security control bypassed, or cross-organisation data leakage | Blocks acceptance unconditionally |
| **High** | A core lifecycle action (application/approval/disbursement/repayment/collections) fails, produces wrong output, or requires a workaround | Blocks acceptance unless explicitly waived in writing on the Acceptance Form |
| **Medium** | A non-core feature fails, or a core feature fails only under a rare/edge condition with a known workaround | May be accepted with a documented follow-up date |
| **Low** | Cosmetic, wording, or a genuinely optional/deferred item | Does not block acceptance |

## Workflow

1. A failed row in the Test Execution Register (or anything found
   outside it during pilot use) gets a new row here, same Test ID if
   applicable.
2. **Status** moves `Open → In Progress → Fixed (awaiting retest) →
   Retested: Pass` or `Retested: Fail` (loop back to In Progress) or
   `Accepted Risk` (Medium/Low only, requires the accepting party's
   name).
3. A defect is only closed once retested against the *same* real
   infrastructure it was found on, not merely against the development
   sandbox.
4. Per [[feedback_quality_over_speed]]: root-cause and fix for real —
   do not close a defect by narrowing the test that caught it, unless
   the test itself was proven wrong.

## Register

| Defect ID | Test ID | Date Found | Severity | Description | Root Cause | Fix / Status | Retested By | Date Closed |
|---|---|---|---|---|---|---|---|---|
| _(none logged yet)_ | | | | | | | | |

---

## Known, accepted limitations — not defects

These are documented, deliberate scope boundaries from engineering
history. If pilot testing rediscovers one of these, **do not log it as
a new defect** — cross-reference it here instead, and escalate only if
its actual impact during the pilot is worse than described.

| Item | Description | Reference |
|---|---|---|
| ClamAV real-virus detection | Fail-closed-when-absent behavior is verified; actual malware detection (e.g. EICAR file) has never been exercised against a real ClamAV install anywhere, including in this pilot's own pre-launch checks unless Test D9 has been run and passed | Runbook §8 |
| Real SMTP provider round trip | STARTTLS/auth/inbox delivery against a real provider was never verified before pilot launch unless Test G6 has been run and passed; only the wire protocol against a local debug server was confirmed in development | Runbook §12 |
| Postgres TLS hostname verification | Certificate *chain* trust is verified; hostname-to-certificate matching is not automatically enforced | Runbook §2 |
| Single-instance deployment only | KYC document storage (local disk) and `Monitoring.Store` (in-memory ETS) do not support horizontal scaling; the pilot must run as one app instance | Runbook §9, §11 |
| No key rotation | `KYC_ENCRYPTION_KEY`/`MFA_ENCRYPTION_KEY` rotation is not built; losing a key makes its protected data permanently unreadable (KYC) or forces re-enrollment (MFA) | Runbook §9, §9a |
| No external alerting | `/admin/system-health` and structured logs exist; nothing pages a human unless the pilot's own infrastructure wires that up | Runbook §11 |
| Backup destination is local-only | No off-site backup adapter is built; a host-level disaster still loses the backups alongside the primary data unless the pilot adds a real off-site destination | Runbook §10 |
| Postgres dump not separately encrypted | KYC files are ciphertext before backup; the SQL dump itself is plaintext unless the backup destination provides at-rest encryption | Runbook §10 |
| No customer licensing enforcement | The renewable 12-month licence module is deliberately not built yet; pilot entitlement is administered manually under the signed pilot agreement | Pilot-Readiness Checklist §4 |
