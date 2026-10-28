# ADR-0084: Collecting what's owed

- **Status:** Accepted
- **Date:** 2026-10-28
- **Sub-phase:** P15.5

## Context

Cinemas pay AfriCinemas' monthly invoices (ADR-0083) themselves. The owner decided on
2026-10-28:
- an invoice is paid **in full**, with the amount filled in and not editable;
- a cinema can **dispute** an invoice;
- reminders go 2 days before the due date, on the day, then 3 and 7 days after;
- the **grace period** is 5 days after the due date before suspension is possible.

## Decision

**Pay now.** Each invoice still owed has a Pay now form on the Billing page. The
amount is shown in a read-only field and the person paying gives only an M-Pesa
number. The server sends an M-Pesa prompt (STK push) for the invoice's amount, never a
figure from the page.
- The account reference is the invoice number.
- The payment goes to AfriCinemas' own Daraja app (`DARAJA_*`, the paybill
  `AFRICINEMAS_BILLING_PAYBILL` names), never to a cinema's.
- M-Pesa takes whole shillings, so a statement's `payable_cents` is the amount due
  rounded half up, with the rounding shown on the statement and the PDF.
- Only staff who read financial reports may pay, one prompt at a time per invoice.

**Settling, as bookings do** (ADR-0018):
- Safaricom's callback (`/hooks/mpesa-bill/{token}`) is only filed. M-Pesa is then asked
  directly, by a job every few seconds or when the Billing page asks.
- **Paid**, for the invoice's amount, while it's still owed: the invoice is marked paid.
  A receipt is claimed once, in the same namespace as bookings, so it can't pay twice.
- **Paid but it can't apply**: the invoice was already paid or waived, the amount
  differs, or the receipt was used. The payment is **unmatched** and listed in the
  console. A super admin either matches it to one of that cinema's invoices still owed,
  for exactly its amount, or records how it was refunded.
- **Failed, cancelled or unanswered** after 15 minutes: the invoice is still owed.

A payment with the invoice number typed in by hand at the paybill (C2B) isn't received
yet. That needs Daraja's C2B confirmation URL registered on AfriCinemas' paybill once
it's live, and would feed the same unmatched list.

**Due, overdue, paid.**
- An invoice is overdue from the day after its due date.
- Collecting fields (when paid, the dispute, its decision) are set on the Statement
  later. The figures never change (ADR-0083).
- A dispute decided as **waived** leaves nothing to pay. Credit notes are still to come.

**Reminders.** They go to the cinema's owners on the schedule above, each once (a
claim per invoice and kind). A run that missed a day sends only the latest one
reached. No reminder goes while the invoice is disputed, or once it's paid.

**Disputes.** On an invoice still owed, a finance reader says what's wrong (10 to
1,000 characters).
- This opens a Help request (category `invoice_dispute`, in the support inbox) and pauses
  reminders and suspension for that invoice.
- A super admin decides it **stands** or is **waived**, with a note the cinema sees, and
  the owners are emailed.

**Overdue banner.** Staff who can pay see a banner on every back-office page for an
overdue invoice.

**Suspension, only by a person.**
- A cinema can be suspended once an invoice is more than 5 days overdue and not
  disputed. It takes staff with `platform.suspend` (super admins and reviewers, as the
  platform roles define it) and a reason.
- The cinema is then no longer public:
  - its storefront says "This cinema isn't available right now";
  - `require_live` refuses new orders and payments online and at the counter;
  - its back office tells everyone why. It can still pay, and payments already under
    way still settle.
- **Reinstate** undoes it.
- Both are in the platform audit log and emailed to the owners.

## Consequences

- The paybill instructions on statements now point to Pay now. `AFRICINEMAS_BILLING_PAYBILL`
  must name the same paybill as AfriCinemas' `DARAJA_SHORTCODE` once live.
- Payments by hand at the paybill (C2B) wait for the live paybill.
- The browser tests can't move the server's clock. Overdue invoices, reminders and
  suspension are tested in-process (`tests/integration/collecting_tests.jac`), with the
  test-only clock.
