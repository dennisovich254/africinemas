# Before going live: what couldn't be tested by hand yet

Started 2026-10-28, after P15.3 (each cinema's own M-Pesa), P15.4 (monthly statements
and invoices) and P15.5 (collecting what's owed). Each item below works in automated
tests, or isn't built yet, but hasn't been tried for real. Revisit each one before the
first real cinema sells, and tick it once it's been tried on staging or live.

Most of P15.5 can be tried by hand with a shifted clock: run the server under
`faketime -f "+Nd" jac run --dev main.jac`. That covers overdue invoices, reminders and
suspension, so they aren't listed here.

## M-Pesa against Safaricom for real

- [ ] **A cinema connects its own live Daraja app** (P15.3): real consumer key, secret,
  passkey and shortcode, from Safaricom's production portal rather than the sandbox.
- [ ] **The KES 1 test payment** reaches the cinema's own paybill or till, and the
  prompt on the owner's phone shows the business's real registered name. The name
  check only compares what the owner typed, because Daraja can't look a paybill's name up.
- [ ] **A Till** (Buy Goods) pays the till number, signed with the store number.
- [ ] **Customers' payments go to each cinema's own paybill**, and each is checked with
  that cinema's keys. Locally the simulator records this; live, check the cinema's
  M-Pesa statement.
- [ ] **A change of paybill waits its 24 hours** in real time and then takes over, while
  payments in flight still settle with the old account.
- [ ] **Safaricom's callbacks reach us**: `DARAJA_CALLBACK_BASE` is a public https
  address, and both `/hooks/mpesa/{token}` (bookings) and `/hooks/mpesa-bill/{token}`
  (invoices) receive them.
- [ ] **Real timeouts and failures**: a customer who never answers, enters the wrong
  PIN or has too little money. The simulator scripts these by phone number; real
  M-Pesa's result codes and timings may differ.
- [ ] **`AFRICINEMAS_MPESA_KEY` is backed up** with the deployment secrets, and a
  restore on a new server still opens the cinemas' sealed keys. Losing it means every
  cinema connects again.

## AfriCinemas' own paybill (P15.4, P15.5)

- [ ] **AfriCinemas' live paybill exists** and `AFRICINEMAS_BILLING_PAYBILL` is set to
  it. Until then statements show the placeholder 000000 and say payments are tests.
- [ ] **`DARAJA_SHORTCODE` and the `DARAJA_*` keys are AfriCinemas' own live app for
  that same paybill.** Pay now sends invoice prompts through it.
- [ ] **Pay now for real**: an owner pays an invoice from Billing, the money arrives in
  AfriCinemas' paybill with the invoice number as the account, and the invoice reads Paid.
- [ ] **Rounding to whole shillings**: a KES 49.80 invoice is paid as KES 50. Confirm the
  accountant is happy with the rounding line, or switch to rounding down.
- [ ] **Paying by hand at the paybill (C2B) isn't built.** A cinema that types the
  invoice number into M-Pesa itself isn't recorded yet. That needs Daraja's C2B
  confirmation and validation URLs registered on the live paybill, then matching to the
  invoice, or to the unmatched list.
- [ ] **The unmatched-payments list** (a payment for an invoice already paid or waived,
  or for another amount). Matching by hand and recording a refund are tested
  in-process only: the simulator can't produce one by hand. Try one on staging with
  two real prompts.
- [ ] **Refunding an unmatched payment** is done outside the app (M-Pesa reversal or a
  transfer). Agree who does it and how it's recorded.

## The monthly job, in real time

- [ ] **Statements go out on the 1st by themselves**, from the hourly job, without
  pressing *Issue what's due now*. Locally `AFRICINEMAS_BILLING_EARLY` was used instead.
  Production must never set it.
- [ ] **With more than one server copy**, each statement, invoice number and reminder is
  still issued once. The claims are tested in-process, not on the real deployment.
- [ ] **A cinema in another time zone** gets its statement on its own 1st, with its own
  local days.
- [ ] **Invoice numbers stay in order** over months on the real database (AC000001,
  AC000002, …). A server stopping mid-issue can leave a gap. Check that's acceptable
  for KRA.

## Emails (P16.6)

- [ ] **Real delivery**: until a provider is chosen, every email (invoice paid, reminders,
  dispute answers, suspended and reinstated, M-Pesa connection changes) is only written
  to the outbox. Check each one arrives, not as spam, once SMTP is set up.
- [ ] **Owners with no email on their staff record** get no billing emails. Check every
  live cinema's owners have one.

## Tax and records (P15.4)

- [ ] **VAT**: ticking VAT on the registrations checklist adds 16% to new statements.
  Confirm the rate, and whether VAT is charged before or after a credit brought forward,
  with the accountant once AfriCinemas registers.
- [ ] **eTIMS**: invoices aren't submitted to KRA yet. This is needed once AfriCinemas
  registers for eTIMS.
- [ ] **Credit notes aren't built.** A dispute can only stand or be waived, and a waived
  invoice simply has nothing to pay. Check with the accountant whether waiving needs a
  formal credit note.
- [ ] **The PDF's wording and layout** suit an invoice under Kenyan rules: AfriCinemas'
  KRA PIN, address and the cinema's PIN may need to be on it.

## Screens with no browser test yet

- [ ] **Amounts below zero in the back office** (refunds, fee credits) read `-KES 150.50`.
  No screen can make a refund yet, so this hasn't been seen in a browser. Revisit when
  the refund screen is built.
- [ ] **A refund screen** (P15.2's follow-up): refunds and their fee credits exist only on
  the server (`record_refund`).
- [ ] **The Issue, dispute and match buttons are hidden** for platform staff who can't
  use them (reviewers, support). The server refuses them, but no browser test signs
  in as a reviewer.

## Decisions to confirm

- [ ] **Who may suspend a cinema**: today anyone with `platform.suspend`, which includes
  reviewers as well as super admins. The plan said super admins.
- [ ] **Who may pay an invoice**: anyone who reads the cinema's financial reports
  (owner, general and finance managers, auditors). Check auditors should be able to.
