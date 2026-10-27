# ADR-0081: Money rules: integers, whole shillings, rounding once, nothing lost or invented

- **Status:** Accepted
- **Date:** 2026-10-27
- **Context:** the owner asked that money handling follow industry practice, so that no
  amount is ever created or lost by rounding (2026-10-27).

## Decision

`core/money.jac` holds the rules, and the money code follows them.

1. **Integers only.** Every amount is an int of cents. Rates are ints of basis points.
   Nothing is stored, summed or compared as a float.
2. **Whole shillings for whatever a customer pays.** M-Pesa charges whole shillings.
   - Ticket prices were already whole shillings.
   - Now snack prices, venue snack prices and add-on prices are too. Before this, a
     price such as KES 150.50 was accepted: M-Pesa would have been asked for less, and
     settlement would have flagged the mismatch and refunded, so no money was invented
     but the sale failed.
   - `valid_push` refuses any M-Pesa request that isn't whole shillings, so nothing is
     ever truncated.
3. **Amounts and rates from outside are parsed as text with `Decimal`**, never through
   float:
   - M-Pesa's confirmed amount (`cents_of_shillings`). Anything that isn't whole cents
     counts as nothing paid, so settlement flags it;
   - the console's percentages (`basis_points_of`), with at most two decimals.
4. **Rounded once, half up, per order.**
   - Each category's exact fee is `base × bp` (plus any flat amount per item), in
     ten-thousandths of a cent.
   - The order's fee is their sum, rounded once.
   - The parts are allocated from it by the **largest-remainder method**, so they
     always add up to the fee.
   - The rule is written into schedule 1 of the cinema agreement.
5. **Cumulative refund credits.** A credit is the fee on everything refunded so far
   (rounded once), less the credits already given, so partial refunds credit exactly
   what one full refund would. Every eligible refund records its credit, even when it
   rounds to 0, so the running total stays right.
6. **No refund beyond what was paid.** A refund larger than what's left (payments less
   refunds, money owed back and reversals) is refused.
7. **Invariants checked by tests:**
   - fee parts add up to the fee, on 1,000 random orders;
   - the fee is the exact amount rounded once;
   - fee + the cinema's share = what was paid;
   - allocation keeps every cent (2,000 random cases);
   - three partial refunds credit exactly the fee;
   - a cent beyond the order is refused.

## Consequences

- **Fixed for these totals.** Statements and invoices (P15.4) add up each order's
  frozen fee and never round again.
- **Existing snack prices with cents** must be changed before they can be saved again;
  there are none in tests or the pilot.
