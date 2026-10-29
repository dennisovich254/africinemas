# ADR-0088: Customers download their data and delete their account

- **Status:** Accepted
- **Date:** 2026-10-29
- **Sub-phase:** P15.0

## Context

A cinema's customers have the right of access, portability and erasure (Data
Protection Act ss.26, 38 and 40), with deadlines of 7 to 30 days
(`docs/legal/data-requests-procedure.md`). Each cinema answers for its own customers,
so they need a way to do it quickly. Customer accounts belong to one cinema (ADR-0037).

## Decision

On the storefront's **My account**, a customer can:

- **Download my data**: a JSON file (`my_data`) of what the cinema holds about them:
  - the account;
  - their bookings, saved to the account or made with its email, with seats, amounts
    and payments (no ticket QR codes);
  - the offers record;
  - the apps they connected.
- **Delete my account**: after their password (`request_account_deletion`), the
  account is **locked** and deleted **seven days later** unless they press *Keep my
  account* (`cancel_account_deletion`). Owner, 2026-10-29.
  - While it's locked, `require_customer_of` refuses everything but downloading and
    cancelling, and the page shows only that.
  - `delete_due_accounts` (hourly) then removes the sign-in, the customer profile, the
    saved-bookings list and their connected apps.
  - It keeps a record that the account was deleted, with no email or name.

What's **kept**, as the owner decided (2026-10-29), which the page tells the customer:

- **Orders** stay: they're the cinema's sales records, which tax law keeps. The email
  is removed from orders whose showtime has passed. Tickets still to come keep working.
- **The M-Pesa phone** stays with its receipt, as the payment record.
- **The offers record** stays, marked withdrawn, as proof that offers stopped
  (s.40(3)).

## Consequences

- An upcoming order keeps its email after the deletion; it isn't removed later when
  that showtime passes.
- Staff accounts aren't covered: staff manage theirs with their cinema.
