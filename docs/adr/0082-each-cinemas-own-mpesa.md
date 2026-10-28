# ADR-0082: Each cinema's own M-Pesa, with sealed keys and a 24-hour wait on changes

- **Status:** Accepted
- **Date:** 2026-10-28
- **Sub-phase:** P15.3

## Context

Customers' M-Pesa payments must go straight to each cinema, not through AfriCinemas.
Collecting them in one AfriCinemas paybill and paying cinemas out would mean holding
other people's money, which needs authorisation from the Central Bank of Kenya as a
payment service provider (National Payment System Act 2011, NPS Regulations 2014).

The owner looked at splitting each payment as it's made through a licensed gateway
(Paystack's split payments, for example) and chose not to (2026-10-28): **cinemas'
own paybills, and a monthly bill for AfriCinemas' fees** (P15.4, P15.5). M-Pesa itself
can't split a payment between two paybills.

## Decision

**Each cinema connects its own Daraja app** under Settings → Payments: a Paybill (its
number), or a Till (the store number Daraja signs with and the till number customers
pay). It enters the registered name and the app's consumer key, consumer secret and
passkey, plus the owner's password again. The page has a step-by-step guide to
getting the keys from Safaricom's developer portal.

**Who may connect:**
- the owner only (`tenant.verification`); settings staff see the status, never keys;
- only once AfriCinemas has verified the cinema (P14.5);
- only when the registered name matches the verified business's, ignoring case,
  punctuation and how "Limited" or "Company" is written. Daraja has no way to look a
  paybill's name up, so this checks what the owner declares. The test payment's
  prompt on the owner's phone shows the real name, and the guide tells them to check
  it.

**Keys are sealed, never shown again.** `core/payments/secret_box.jac` seals each key
with AES-256-GCM. The key is derived with HKDF-SHA256 from `AFRICINEMAS_MPESA_KEY`,
a secret in the server's environment, never in the database. The cinema, the
account's version and the field are bound in as associated data, so a sealed value
copied to another cinema, version or field doesn't open. Without the secret nothing
is sealed and connecting is refused. Answers show only the consumer key's last four
characters. The `MpesaAccount` nodes belong to the cinema's principal and aren't
granted to its staff group.

**Every connection is a new version, never an edit.** A payment records the version
it was made with (`PaymentIntent.mpesa_version`) and is always sent and checked with
that version's keys (`provider_for`), so a switch never strands payments in flight.

**A KES 1 test payment comes first.** It's sent from the owner's phone with the new
keys; the version is used only once M-Pesa says it was paid, for exactly KES 1.

**A change waits 24 hours** from when it was asked for, even after its test passes.
Payments keep going to the account in use. Every owner gets an email for every
connection, and the change can be cancelled until it's in use. An owner whose
account was taken over has a day to notice. The account in use is simply the latest
tested version whose time has come, so no job is needed to make the switch.

**No AfriCinemas paybill fallback in production.** Version 0, the platform's own
`DARAJA_*` app, is only for the sandbox and tests. Against live Daraja, or with
`AFRICINEMAS_OWN_MPESA=required`, a cinema that hasn't connected can't take M-Pesa
(`mpesa_not_connected`). Cash at the box office is unaffected.

## Consequences

- AfriCinemas never holds a cinema's money, so it needs no payment licence. Its fees
  are owed, not deducted, so P15.4 (statements and invoices) and P15.5 (collecting
  what's owed) matter.
- **Losing `AFRICINEMAS_MPESA_KEY` means every cinema connects again.** It's backed up
  with the other deployment secrets. Changing it isn't supported yet: the sealed
  values carry a version (`v1.`), so a second key can be added later.
- The test payment's KES 1 goes into the cinema's own paybill, from its owner.
- The name check relies on the owner's word plus their phone's prompt. A reviewer
  can compare names in the audit log (`mpesa.connected`).
- Customers' callbacks still arrive at one URL per payment token; which cinema's keys
  check them comes from the payment, not from the callback.
