# ADR-0085: Reconciliation and AfriCinemas' takings

- **Status:** Accepted
- **Date:** 2026-10-28
- **Sub-phase:** P15.6

## Context

Cinemas are paid straight into their own paybills (ADR-0082), so nobody but us records
what each payment was for. Before going live we need to know when our records and
M-Pesa's disagree, and when the box office's cash doesn't add up.

The plan suggested Daraja's Transaction Status lookup for every payment. That needs
each cinema's "initiator" user and a security credential (a password encrypted with
Safaricom's certificate), which Settings → Payments doesn't ask for. On 2026-10-28 the
owner chose not to ask cinemas for them.

## Decision

Three checks, all turning what doesn't add up into an **exception**
(`core/payments/reconcile.jac`):

1. **Every day, M-Pesa is asked again** about each payment of the last 3 days. It uses
   the STK status query and the account the payment was made with: the keys we already
   hold. Each payment is checked once (a claim).
   - `not_paid`: we sold on it, but M-Pesa says it wasn't paid.
   - `no_order`: M-Pesa says it was paid, but nothing was sold for it.
   - `amount_differs`: M-Pesa's amount isn't ours.
   - `receipt_twice`: one receipt on two of our payments.
2. **An M-Pesa statement the cinema uploads** (the CSV from Safaricom's M-Pesa portal) is
   matched line by line, by receipt, for the time it covers. This catches money that
   reached the paybill without going through us, which the daily check can't see.
   - The columns are found by name (Receipt No., Completion Time, Paid In, and if present
     Transaction Status and A/C No.), after any lines about the account.
   - Only completed money in is read, and the KES 1 test payments (account TEST, P15.3)
     are skipped.
   - `not_in_app`: on the statement, but no order took it.
   - `not_in_statement`: our M-Pesa payment, within the statement's time, isn't on it.
   - `amount_differs`.
3. **A cash-up at the box office.** A member of staff counts the cash taken since their
   last count (not the float) on the Box office page's *Count cash* tab.
   - The count is compared with the cash sales, less cash refunds, recorded under their
     name since then.
   - What they recorded is shown only after they've counted, so the count is honest.
   - A difference is `cash_short` or `cash_over`.

**Exceptions are kept once.** A claim on the cinema, kind and what it's about means
checks that run again add nothing.
- Staff who read the cinema's financial reports see them on a **Reconciliation** page,
  upload statements there, and mark each resolved with a note (audit-logged). A
  resolved exception stays listed.
- The console's Reconciliation page shows every cinema's open exceptions to platform
  staff.

**AfriCinemas' takings** (`core/billing/takings.jac`) are on the console's overview,
per month and per cinema:
- fees earned (charged less credited, by the cinema's local month);
- what was invoiced (each statement's payable amount);
- what of that is paid, overdue or waived.

The platform's totals are the sums of the cinemas', so what's invoiced equals the sum
of the invoices.

## Consequences

- Money paid to a cinema's paybill outside AfriCinemas is only seen when its statement
  is uploaded. Statements aren't fetched automatically; that would need the initiator
  credentials.
- Daraja's STK query may stop answering for old prompts. The daily check looks back 3
  days and checks each payment once, so a payment it couldn't ask about is just left
  unchecked.
- The statement's column names are taken from Safaricom's portal export, and should be
  checked against a real one (`docs/before-go-live.md`).
- Cash counts are per member of staff, since their last count, so there's nothing to
  open or close. A member who never counts is never checked.
