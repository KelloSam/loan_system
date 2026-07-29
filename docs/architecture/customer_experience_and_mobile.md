# Customer Experience and Mobile Application Specification

This document exists so that customer-facing access — as distinct
from the staff-facing `/admin` side of the app — has a written plan.
Without it, "we'll build a mobile app eventually" has no home, no
sequencing, and no way to check whether earlier steps actually laid
the groundwork it depends on. It doesn't get a numbered Step of its
own: it's cross-cutting, threaded through Steps 4 and onward, and
revisited here as those steps land.

## The identity foundation (Step 4 — done)

Customer access rests on three distinct identities, not one blurred
concept:

| Identity | Owns | Module |
|---|---|---|
| **User** | Login credentials only — email, password hash, status, session invalidation. No opinion on who the person *is*. | `MiwayCreditCore.Accounts.User` |
| **Customer** | The borrower business record — the entity with loans, balances, KYC status. Can exist with no portal access at all (most customers today are registered by staff and never log in). | `MiwayCreditCore.Customers.Customer` |
| **CustomerUser** | The relationship that *authorises* portal access — a real foreign-key join from a `User` to the `Customer` it may act as, replacing an old email-string match with zero referential integrity. One `User` maps to exactly one `Customer`; a `Customer` isn't restricted to one login, leaving room for a business customer with more than one authorised portal user later. | `MiwayCreditCore.Accounts.CustomerUser` |

This split is what makes everything below possible: a native mobile
app, when it arrives, authenticates the same `User` and resolves the
same `CustomerUser` relationship the web portal already uses today —
it's a new client, not a new identity model.

## The sequence

```
Backend foundation → customer authentication → secure responsive
web portal → pilot testing → native mobile application
```

Each phase is a real prerequisite for the next, not just an ordering
preference:

### 1. Backend foundation — done (Steps 3-7)

Bounded contexts, multi-organisation isolation, server-enforced
permissions, and now customer identity/KYC. A mobile app calling
straight into an unstable or unscoped backend would just move the
same problems onto a second surface.

### 2. Customer authentication — done (Step 4)

`CustomerUser` plus session-based login under `/client`, gated by
`EnsureCustomerPlug`. Password reset, account status, and failed-login
handling are shared with staff login through the same `User` identity
— there is no separate, weaker authentication path for customers.

### 3. Secure responsive web portal — in progress, further along than "not started"

`/client/dashboard` and `/client/loans` (`CustomerDashboardController`,
`CustomerLoanController`) already exist, session-gated, and built with
responsive Tailwind layout (breakpoint classes throughout, a real
viewport meta tag in the root layout) rather than a desktop-only UI
that would need retrofitting. What exists today is a read-only view —
loan list, balances, next payment due. Not yet built: any portal
action that *writes* (a customer-initiated application, a self-serve
payment, a document upload against their own KYC record). Those are
natural extensions of this same phase, not a new one.

### 4. Pilot testing — not started

Deliberately not skipped past. Before a native app is built, the web
portal should carry real customers for a period, so mobile app
requirements are informed by actual usage (which features get used,
what breaks on real devices/networks, what customers actually ask
for) rather than guessed upfront. No infrastructure decision is
required to start this phase — it's an operational/rollout decision
for whoever runs Miway's pilot, not an engineering task.

### 5. Native mobile application — deferred, not forgotten

Explicitly out of scope until the above phases are real, not
hypothetical. When it starts, it is a new client against the same
identity model and the same context boundaries — it does not imply
new backend concepts. Candidate shape once it's time to plan for real
(not a commitment, just what to expect the decision points to be):

- Same `User` + `CustomerUser` authentication, likely token-based
  (the web portal's cookie session doesn't translate to a native app)
  rather than a change to the identity model itself.
- Whatever the web portal's read/write surface has grown to by then
  becomes the app's initial feature set — the app should not invent
  capabilities the web portal never had a chance to validate first.
- Push notifications for payment due dates / KYC status changes would
  route through the reserved `Notifications` context
  (`context_boundaries.md`), not a bespoke mobile-only mechanism.

#### Candidate initial screen list (illustrative, not a spec)

Mirrors **only** the read-only capability the web portal has actually
validated today (confirmed directly against `CustomerDashboardController`
and `CustomerLoanController`, not assumed) — nothing here invents a
capability the portal hasn't had a chance to prove out first, per this
section's own principle above:

- Application list and next-payment-due summary — exactly what
  `/client/dashboard` (`CustomerDashboardController.index/2`) renders
  today.
- Loan detail: account status/outstanding balance, interest detail,
  and the full repayment schedule — exactly what `/client/loans/:id`
  (`CustomerLoanController.show/2`) already renders today via
  `Lending.compound_interest_details/1` and
  `Lending.list_installments_for_account/2`.

Explicitly **not** on this list yet, each for the same reason — none
of these exist on the web portal (confirmed: no KYC status and no
payment/transaction data is shown to a customer anywhere today), so
there's no validated behavior yet for a mobile screen to mirror:

- KYC document status or upload.
- Payment transaction history.
- Customer-initiated loan applications.
- Customer self-service payment submission.

If and when the web portal grows any of this surface, this list grows
with it — not before. As stated above, none of this is a commitment
to build a mobile app on any particular timeline; it's only a
placeholder for what a first screen list would plausibly draw from.

## API boundary for customer operations — decision

A prior planning document asked for "clear API boundaries around
customer operations" as part of mobile groundwork. Decision: **no
versioned JSON API is being built now.**

Today's API boundary already exists — it's the bounded-context
discipline this app has followed since Step 3: `Applications`,
`Risk`, `Lending`, `Payments`, `Accounting`/`GeneralLedger`,
`AuditLogs` each expose only their own public context functions, and
the only client calling into them is server-rendered HTML
(`Phoenix.Controller` + `.heex` templates). There is no JSON API
surface anywhere in this app today.

Building a real versioned JSON API against zero actual consumers would
be premature abstraction — exactly the kind of ahead-of-need building
this project has avoided at every prior step. It waits until a native
mobile client is actually greenlit and its real data-shape needs are
known from the web portal's own pilot — the same "pilot before you
build the next thing" gate Phase 4 above already applies to the mobile
app itself; the API gets the identical gate, not an earlier one.

**Assumption correction:** that same prior planning document treated
`Notifications` as if it already delivers messages. It does not —
`docs/architecture/context_boundaries.md` lists it as `Notifications —
unscheduled`: reserved, no schema, no implementation, nothing routes
through it today. Any reference elsewhere assuming otherwise should be
read as aspirational, not current state.

## What this document is not

Not a commitment to a timeline, a technology choice (React Native vs.
Flutter vs. platform-native), or a budget. It is the answer to "is
customer mobile access being ignored" — no: its identity and security
foundation started in Step 4, its first usable interface is the
responsive web portal already taking shape, and the native app has a
defined place in the sequence rather than an undefined one.
