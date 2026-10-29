# ADR-0087: Staff confirm their email before working

- **Status:** Accepted
- **Date:** 2026-10-29

## Context

Owners confirm their email before creating a cinema (P14.2). Staff joined through an
invite link that the owner copies and sends them, so nothing proved their email was
theirs. The "Confirm your email" banner still told them they'd need it "to create a
cinema and to go live", which isn't their work. On 2026-10-29 the owner decided every
member of staff confirms their email, and that their features stay locked until they
do.

## Decision

- **`start_shift` refuses `confirm_email` until the member's sign-in email at the
  cinema is confirmed** (`core/tenancy/tenant_api.jac`). Every staff action needs a
  shift (ADR-0006), so this one check locks their role's work: selling, scanning and
  managing. Pages that don't need a shift (the overview, their profile) still open.
  - The refusal names the email and points to the banner's Send again.
  - As at create_cinema, only a record with an email address is checked.
- **The banner shows for everyone, worded for their role.**
  - In the back office it lists what's locked, from the member's permissions
    (`unlocks_for` in `web/backoffice/nav.jac`): "Until you do, you can't start a
    shift, so you can't sell at the box office…".
  - On Your cinemas: creating a cinema and going live for an owner, or someone with
    no cinema yet; starting a shift for other staff.
- **The shift banner says why a shift didn't start**: the server's message, not "Try
  again".

## Consequences

- Staff can't work until email reaches them: the email provider must be live before
  go-live (`docs/before-go-live.md`).
- A shift opened before this change keeps running until it ends.
