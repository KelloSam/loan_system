# Miway CreditCore — Formal Pilot Acceptance Form

This form records the formal decision to proceed with (or withhold)
the first controlled pilot of Miway CreditCore, based on the evidence
gathered in the three companion documents. It is a record of a
decision made by named people on a specific date — not a checklist to
tick off casually, and not something this codebase or any automated
process can complete on its own.

## 1. Scope of this acceptance

- **System:** Miway CreditCore, commit `_______________` (record the
  exact git SHA deployed for the pilot — do not accept against a
  moving target).
- **Pilot organisation:** _______________
- **Pilot period:** from ______________ to ______________
- **Pilot agreement reference:** _______________ (the signed agreement
  governing the time-limited pilot entitlement — see Pilot-Readiness
  Checklist §4, licensing module deliberately not built for this
  round)

## 2. Evidence reviewed

| Document | Reviewed? | Outstanding items (if any) |
|---|---|---|
| `MIWAY_CREDITCORE_PILOT_READINESS_CHECKLIST.md` — §2 (deployment configuration) fully complete | ☐ Yes ☐ No | |
| `MIWAY_CREDITCORE_PILOT_READINESS_CHECKLIST.md` — §3 (evidence required before launch) all items satisfied | ☐ Yes ☐ No | |
| `MIWAY_CREDITCORE_PILOT_TEST_EXECUTION_REGISTER.md` — every row `Pass` or accepted `Blocked` | ☐ Yes ☐ No | |
| `MIWAY_CREDITCORE_PILOT_DEFECT_REGISTER.md` — no open Critical or High defect | ☐ Yes ☐ No | |
| `MIWAY_CREDITCORE_PILOT_DEFECT_REGISTER.md` — every open Medium/Low defect has a named accepting party and follow-up date | ☐ Yes ☐ No | |
| Automated test suite green at the deployed commit (record count and date) | ☐ Yes ☐ No | Tests: _____ Date: _____ |

## 3. Explicit risk acknowledgements

The signatories confirm they understand and accept the following,
independent of defect status (these are known, documented scope
boundaries, not bugs — see the Defect Register's "Known, accepted
limitations" section):

- ☐ The renewable customer licensing module is not built; this pilot's
  entitlement is time-limited and administered manually by Miway.
- ☐ Backups are not yet stored off-site (unless this has been
  remediated before this pilot — state which):
  _______________________________________________
- ☐ ClamAV real-malware detection has / has not been verified against
  a live test file on this deployment (circle one). If not verified,
  state the compensating control accepted for the pilot period:
  _______________________________________________
- ☐ Real SMTP delivery has / has not been verified end-to-end on this
  deployment (circle one).
- ☐ This deployment runs as a single application instance; no
  horizontal scaling is supported.
- ☐ Key rotation for KYC/MFA encryption keys is not built; the
  signatories understand the operational impact of key loss described
  in the Runbook (§9, §9a, §10).

## 4. Decision

☐ **Accepted** — the pilot is authorized to proceed as scoped above.

☐ **Accepted with conditions** — proceed, subject to the following
being resolved by the stated date(s):

```
_________________________________________________________________
_________________________________________________________________
```

☐ **Not accepted** — the pilot does not proceed. Reason:

```
_________________________________________________________________
_________________________________________________________________
```

## 5. Signatories

| Role | Name | Signature | Date |
|---|---|---|---|
| Engineering sign-off (confirms §2 evidence is accurate) | | | |
| Business/product sign-off (confirms scope and risk acceptance) | | | |
| Pilot organisation representative (if their own sign-off is part of the agreement) | | | |

## 6. Post-acceptance

- File this signed form alongside the exact commit SHA and the
  completed Test Execution Register and Defect Register — together
  they are the evidence record for this pilot, not just this form
  alone.
- Any Medium/Low defect accepted with a follow-up date must be
  tracked to that date, not forgotten once the pilot starts.
- A pilot retrospective (what broke, what the real infrastructure
  taught that this document's assumptions got wrong) should feed back
  into the Deployment Runbook and this checklist before the *next*
  organisation's pilot, so each pilot after the first gets easier, not
  repeated from scratch.
