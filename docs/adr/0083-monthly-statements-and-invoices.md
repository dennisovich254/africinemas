# ADR-0083: Monthly statements and invoices

- **Status:** Accepted
- **Date:** 2026-10-28
- **Sub-phase:** P15.4

## Context

Cinemas are paid straight into their own paybills (ADR-0082), so AfriCinemas' fees
(ADR-0080) are owed, not deducted. Each cinema needs a monthly bill it can check
against its own Reports, and AfriCinemas needs invoice numbers that are never given
twice, for KRA's eTIMS once it registers.

## Decision

**One Statement per cinema per month**, issued on the 1st of the month in the cinema's
own time zone, for the month before (`core/billing/statements.jac`). It holds the
statement and the invoice together:
- bookings, and gross takings by channel (online, box office M-Pesa, box office cash);
- refunds and net takings;
- AfriCinemas' fees charged, credited back on refunds, and what they come to;
- a credit brought forward, VAT, the amount due and any credit carried forward;
- one line per order: its reference, day, channel, what was paid and refunded, and the fee.

**Built from the same entries as Reports.** It reads the same ledger and fee entries
for the month's local days (`cinema_records`), so a statement and that month's
Reports agree.

**It never changes once issued.** All of it is worked out and stored when it's issued.
A fee credit for a refund made after the month is dated when it's given, so it's on the
next month's statement. Correcting a mistake by hand will be a **credit note**, not an
edit. Credit notes aren't built yet.

**Credits carry forward.** When a month's credits come to more than its fees, nothing
is due, and the credit comes off the next statement before VAT. A month with nothing at
all on it gets no statement, and any credit waits for the next one that does.

**VAT** is 16% of what's owed, but only once a super admin has ticked VAT on the
registrations checklist (P15.0b). Before then the statement says there's no VAT.

**Invoice numbers.** The number is AC and six digits (AC000001, …), and it's also the
account number for paying. Each number is a permanent claim (ADR-0007), so it's never
given twice or reused. A pointer only says where to start looking. A server stopping
between claiming a number and saving its statement can leave a gap. Each cinema's
month is claimed too: provisionally while it's being issued, permanently once saved,
or as "nothing" for an empty month. So the hourly job (`issue_statements`), running on
every server copy, issues each statement once.

**Due 5 days after issue** (owner, 2026-10-28). It's paid to AfriCinemas' paybill
(`AFRICINEMAS_BILLING_PAYBILL`) with the invoice number as the account. **Until that
paybill is live**, the placeholder 000000 is shown, and the statement tells cinemas not
to pay yet.

**Who sees what:**
- In the back office, staff who read financial reports (`financial_reports.read`) have
  a Billing page with their own cinema's statements only.
- In the console, platform staff (`platform.read`) see every cinema's.
- A super admin can **Issue what's due now** in case the job missed a month. This is
  in the platform audit log.
- Each statement downloads as a PDF, written by a small text-only writer
  (`core/billing/pdf.jac`) in the standard PDF fonts, with no new dependency.

**Test runs only:** `AFRICINEMAS_BILLING_EARLY=1` makes Issue what's due now bill the
month so far too, so the browser tests have a statement without waiting for the 1st.
Production never sets it.

## Consequences

- Matching payments to invoices, reminders, overdue banners and suspension are P15.5.
- Submitting invoices to eTIMS waits until AfriCinemas registers for it.
- Credit notes are still to build. Until then, a correction is an adjustment that the
  next month's statement will show.
- The job reads each cinema's records once a month. On every other run it only makes
  one claim per cinema.
