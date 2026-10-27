# ADR-0080: The fee on every paid order, with room for each cinema's own terms

- **Status:** Accepted
- **Date:** 2026-10-27
- **Sub-phase:** P15.2

## Decision

**Rates that can change per cinema** (owner, 2026-10-27: "the model can change
seamlessly with each cinema because of negotiations"). `core/legal/fee_rule.jac` now
works like this:

- **Rates are a table keyed `<channel>:<category>`:**
  - the channels are `online` and `counter`;
  - the categories are `tickets` (with the booking fee), `glasses` and `snacks`;
  - each rate is `{"bp", "per_unit_cents"}`: a percentage, and a flat amount per item.

  `<channel>:*` covers any category a version doesn't name. New categories, and other
  structures (a flat fee per ticket, say), need no change to the code that charges
  fees, or to orders already paid.
- **Two levels of versions, each applying from a day:**
  - the platform's **standard**: model C, version 1;
  - a cinema's **own versions** for negotiated terms. A cinema version either sets its
    rates, or returns the cinema to the standard (`"standard": true`).

  `rule_for(cinema, day)` resolves which one applies. P15.1's stored three-number
  versions are read as tables.
- **Who sees and changes it:**
  - **super admins** set a cinema's terms on its page in the console (Fees): agreed
    rates from a day with a note of what was agreed, or back to the standard. Every
    change is in the platform audit log;
  - **the cinema's staff** with the reports permission see their rates in force, and
    whether they're agreed or standard, on the Cinema agreement page.
- **Agreed rates go in writing too.** They're a change to that cinema's schedule 1, so
  they belong in its agreement; the console says so.

**The fee ledger** (`core/payments/fees.jac`):
- **When it's charged.** `confirm_order`, which every paid order passes through
  (online M-Pesa, counter M-Pesa, cash), calls `charge_fee` in the same commit:
  - the channel is the box office when a member of staff took the payment, otherwise
    online;
  - each category's fee is its base times its rate, rounded half up, plus the flat
    amount per item.
- **What's frozen.** The fee is kept on the order (`fee_cents`, `fee_detail`: whose
  rule, which version, the channel, each part), and appended as a `FeeEntry` "fee".
  `confirm_order` runs once per order, so a repeated callback charges once, and a later
  version never changes the fee.
- **Kept apart from the money ledger.** The money ledger is what passed between the
  customer and the cinema. The fee is what the cinema owes AfriCinemas, invoiced
  monthly (P15.4). Keeping them apart leaves every existing takings figure unchanged.
- **Refunds.** `record_refund` adds the money ledger's "refund" and, for an M-Pesa
  refund or a Platform failure, a "fee_credit" for the refunded share (proportional,
  never more than is still owed). Cash refunds credit nothing (clause 5.3).
- **Reports.** They add AfriCinemas' fees, the credits, and the cinema's share (net
  takings less fees), for the period and the venue chosen.

## Not done

- **No refund screen yet.** No screen records a refund to a customer, so
  `record_refund` is used by the test app only (`t_refund`) until the refund flow is
  built.
- **The fee per order** is in the order's record (`fee_detail`). Showing it for each
  order comes with the transactions page (P17.1).
- **Orders paid before P15.2** carry no fee.

## Found on the way

JI-060: an endpoint parameter left out of a request arrives as the text of its
default, so `False` becomes the true string `"False"`. Such parameters are now
required.
