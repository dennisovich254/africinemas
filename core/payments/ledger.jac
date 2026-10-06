"""The payment ledger (P5.5, architecture §37; ADR-0019): money as append-only entries.

Every movement of money for a booking is a LedgerEntry on its order, written in the
same commit as the change that caused it, and never edited or deleted: there is no
function here that changes an entry. Amounts are in cents, positive for money the
cinema receives and negative for money it owes back.

- "payment": M-Pesa confirmed a payment (+ the amount paid).
- "refund_due": money taken that bought nothing (a payment needing attention), owed back
  (- the amount). Plan 5.5's refund flow (§38) adds "refund" when it is paid out.

A booking's balance is the sum of its entries: a confirmed order balances to its total,
a payment that bought nothing to zero.
"""

import from core.clock { now }
import from core.tenancy.models { Tenant }
import from core.tenancy.groups { attach_to_tenant }
import from core.tenancy.principal { node_id }
import from core.booking.models { Order }

glob KINDS: list[str] = [
         "payment",
         "refund_due",
         "refund",
         "reversal",
         "adjustment"
     ];

node LedgerEntry {
    has tenant_id: str,
        order_id: str,
        intent_id: str,
        kind: str,
        amount_cents: int,
        currency: str,
        receipt: str = "",
        note: str = "",
        created_at: str = "";
}

def record_entry(
    cinema: Tenant,
    order: Order,
    intent_id: str,
    kind: str,
    amount_cents: int,
    receipt: str,
    note: str
) -> LedgerEntry {
    # Appends one entry to the order's ledger. Call as the cinema's principal, inside
    # the commit that moves the money.
    if kind not in KINDS {
        raise ValueError(f"unknown ledger entry kind {kind}");
    }
    made = LedgerEntry(
        tenant_id=node_id(cinema),
        order_id=node_id(order),
        intent_id=intent_id,
        kind=kind,
        amount_cents=amount_cents,
        currency=order.currency,
        receipt=receipt,
        note=note,
        created_at=now().isoformat()
    );
    order ++> made;
    attach_to_tenant(made, cinema);
    return made;
}

def balance(entries: list[LedgerEntry]) -> int {
    return sum([e.amount_cents for e in entries]);
}
