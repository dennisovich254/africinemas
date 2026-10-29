# ADR-0086: Counting the cash before signing out

- **Status:** Accepted
- **Date:** 2026-10-29
- **Sub-phase:** P15.6b

## Context

In P15.6 (ADR-0085) a member of the box office could count their cash at any time,
and nothing asked for it. The owner tried it and asked:
- what happens when an amount is typed wrong;
- why a count isn't tied to the end of a shift;
- what happens when someone signs out, or never signs out, without counting.

On 2026-10-29 the owner decided:
- an agent can't sign out without counting;
- if they forget to sign out, the next agent at that venue counts their cash, after
  starting their own shift. The forgotten agent can't count it later, because the cash
  may have changed by then.

Shifts already lasted 8 hours, for the whole server (`AFRICINEMAS_SHIFT_TTL_S`,
ADR-0006). The owner wanted that kept, but changeable by each cinema.

## Decision

- **No signing out with cash uncounted.** Sign out asks for a count when the member has
  cash they haven't counted (`cash_status`, which says only whether there's cash to
  count, never how much). There's no "sign out anyway".
  - Count now opens Box office → Count cash (`/box-office/sign-out`).
  - Once it's saved, "Sign out now" signs them out.
- **Counting doesn't end the shift.** A member can also count at a handover or a cash
  drop and carry on.
- **The amount is checked before it's saved.** A dialog shows it large and in words
  ("one thousand six hundred shillings"), with Change and Save count.
- **A count can be corrected once**, by whoever made it, within 10 minutes
  (`recount_cash`, audit-logged as `cash.recounted`).
  - The CashUp keeps both figures (`first_counted_cents`).
  - The first count's exception is resolved "by the count". The new one is kept if it
    still differs.
- **Cash someone left is counted by the next agent at that venue** (`left_behind`,
  `count_left_cash`, audit-logged as `cash.counted_for`). The venue is where the cash
  was taken: the showtime's, or the snack sale's.
  - **While that member is still on shift** (they may still be working, at another
    till), their cash is only offered: "If they've left, count it". Counting it ends
    their shift.
  - **Once their shift is over** (it ran out), the manager sees `cash_not_counted`
    (`check_cash_counted`, every 15 minutes), and the next agent at the venue must count
    it before a cash sale (`count_left`).
  - The count is recorded as that member's cash, `counted_by` the next agent, and it
    resolves the "not counted" exception.
  - Their own cash from an earlier shift is the same: it's counted before their next
    cash sale (`count_first`). That's what happens when they're the next at the venue
    themselves.
- **Each cinema sets two limits** on Settings → Box office (tenant.settings.update:
  owners, cinema admins, IT admins). Both are kept on the Tenant.
  - Shift length: 8 hours by default, 1 to 12.
  - The most one count may be: KES 500,000 by default, from KES 1,000 to
    KES 10,000,000. A larger count is refused.
  - The limit doesn't depend on what was sold: that would give away the figure the
    count is meant to be blind to.
  - The environment's `AFRICINEMAS_SHIFT_TTL_S` still overrides the shift length, for
    tests and dev.
  - The time each shift started is kept beside its claim (`staff-shift-start`).

## Consequences

- Sign-out's count is enforced in the app, not by `end_shift`. Closing the browser is
  "forgot to sign out", which the next agent handles.
- A venue is assumed to have one cash drawer. Two agents at once at one venue each see
  the other's uncounted cash offered once that other signs out or their shift ends.
- A member's uncounted cash taken at two venues is counted as a whole, at whichever
  venue the next agent is.
- M-Pesa sales aren't blocked by uncounted cash; only cash sales are.
- A general manager can't change the box office's rules: Settings is for
  tenant.settings.update. Giving them that would need a new permission.
