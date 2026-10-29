# ADR-0086: Counting the cash ends a shift

- **Status:** Accepted
- **Date:** 2026-10-29
- **Sub-phase:** P15.6b

## Context

In P15.6 (ADR-0085) a member of the box office could count their cash at any time. The
owner tried it and asked:
- what happens when an amount is typed wrong;
- why a count isn't tied to the end of a shift;
- what happens when someone signs out, or never signs out, without counting.

Shifts already lasted 8 hours, for the whole server (`AFRICINEMAS_SHIFT_TTL_S`,
ADR-0006). The owner wanted that kept, but changeable by each cinema.

## Decision

- **Counting is how a shift ends.** Saving a count closes the member's shift. A new
  one is started from the usual banner.
- **The amount is checked before it's saved.** A dialog shows it large and in words
  ("one thousand six hundred shillings"), with Change and Save count.
- **A count can be corrected once**, by whoever made it, within 10 minutes
  (`recount_cash`, audit-logged as `cash.recounted`).
  - The CashUp keeps both figures (`first_counted_cents`).
  - The first count's exception is resolved "by the count". The new one is kept if it
    still differs.
  - After that, only a manager sorts it out, on the Reconciliation page.
- **Each cinema sets two limits** on Settings → Box office (tenant.settings.update:
  owners, cinema admins, IT admins). Both are kept on the Tenant.
  - Shift length: 8 hours by default, 1 to 12.
  - The most one count may be: KES 500,000 by default, from KES 1,000 to
    KES 10,000,000. A larger count is refused.
  - The limit doesn't depend on what was sold: that would give away the figure the
    count is meant to be blind to.
  - The environment's `AFRICINEMAS_SHIFT_TTL_S` still overrides the shift length, for
    tests and dev.
- **Signing out reminds them.** Signing out with cash not yet counted asks first:
  Count now (which opens Box office → Count cash), or Sign out anyway. `cash_status`
  says only whether there's cash to count, never how much.
- **Cash left uncounted is shown to the manager.** When a shift has ended (signed out,
  or ran out) with uncounted cash, `check_cash_counted` (every 15 minutes) lists it as
  `cash_not_counted`, once per uncounted stretch.
- **That cash must be counted before the next cash sale.** On their next shift the
  member is asked to count it first: Box office opens on Count cash. Cash sales (tickets
  and snacks) are refused with `count_first` until it's counted. When it is:
  - the "not counted" exception is resolved;
  - the new shift stays open.
  The time each shift started is kept beside its claim (`staff-shift-start`) for this.

## Consequences

- A member who counts at a handover has to start a new shift to keep selling.
- M-Pesa sales aren't blocked by uncounted cash; only cash sales are.
- A general manager can't change the box office's rules: Settings is for
  tenant.settings.update. Giving them that would need a new permission.
