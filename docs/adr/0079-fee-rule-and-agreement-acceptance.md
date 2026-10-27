# ADR-0079: The fee rule, and accepting the cinema agreement

- **Status:** Accepted
- **Date:** 2026-10-27
- **Sub-phase:** P15.1

## Decision

**The fee rule** (`core/legal/fee_rule.jac`):
- **The rates.** It holds model C (owner, 2026-10-26):
  - online: 7% on tickets, 3D glasses and the booking fee, and 20% on snacks;
  - box office: 3% on everything.

  Rates are kept in basis points, and each version has the day it applies from. The
  first version applies from 2026-10-26.
- **Who sees and changes it.** Platform staff read it on the console's **Fees** page.
  Only super admins (`platform.settings`) add a version. Every change is in the
  platform audit log.
- **The rules for a new version:**
  - it applies from today or a later day (Africa/Nairobi), never in the past;
  - two versions can't share a day;
  - rates must be between 0% and 50%, with at most two decimals.

  Because of the first rule, no paid order is ever charged differently.
- **What P15.2 uses.** `rule_on(day)` gives the version in force on a day, and 15.2
  freezes that on each order.
- **Changing the rates means a new agreement version.** The rates are schedule 1 of
  the cinema agreement, so cinemas must accept a new version (clause 5.10). The Fees
  page says so.

**Accepting the agreement** (`core/legal/agreement.jac`, `agreement_api.jac`):
- **The current version** is the published one (0.1).
- **Who can do what.** The cinema's own team reads the text
  (`cinema_agreement_text`), which is confidential and never public. Only the owner
  (`tenant.verification`) accepts it, without needing a shift, and only the version
  they were shown: a change since then is refused.
- **What's recorded.** The acceptance is one permanent claim per cinema: the version,
  the owner's account and email, the time, and every earlier acceptance. It's also in
  the cinema's audit log.
- **In the back office:**
  - the **Cinema agreement** page (owner only, beside Verification) shows the text and
    what was accepted;
  - a notice above every page asks the owner to accept it, and tells other staff when
    sales are paused.
- **Enforcement**, at two points:
  - **Going live.** "Accept the cinema agreement" is a go-live essential, so a cinema
    can't submit for review without accepting the current version.
  - **Selling under an old version.** A cinema that accepted an older version can't
    take orders (`require_live`, used by storefront orders, counter sales, snack-only
    sales and added snacks) until its owner accepts the current one.

## Not done

- **Making acceptance part of creating the cinema.** It isn't a step in
  `create_cinema` itself: that would change the 63 places that call it. The owner sees
  the notice the moment the new cinema opens, and can't go live without accepting.
- **Cinemas made before P15.1** that never accepted aren't stopped from selling. There
  are none with real customers yet.
