"""AfriCinemas' fee on every paid order (P15.2, ADR-0080): the fee ledger.

When an order is paid (confirm_order: online M-Pesa, M-Pesa at the box office, cash at
the box office), charge_fee works out the fee from the rule in force for that cinema on
that day (core/legal/fee_rule.jac, rule_for), freezes it on the order (fee_cents and
fee_detail: whose rule, which version, the channel and each category's base, rate and
fee) and appends a FeeEntry, in the same commit as the payment. confirm_order runs once
per order, so a repeated M-Pesa callback can't charge it twice, and a later change of
rates never touches it.

The fee ledger is apart from the money ledger (core/payments/ledger.jac): the money
ledger is what passed between the customer and the cinema, the fee is what the cinema
owes AfriCinemas, invoiced monthly (P15.4). Entries are only ever added:
- "fee": + the fee, owed to AfriCinemas;
- "fee_credit": - the fee on what was refunded, for an M-Pesa refund or one caused by a
  Platform failure; never for a cash refund, which can't be checked (clause 5.3).

The channel is the box office when a member of staff took the payment (recorded_by),
otherwise online. The categories: tickets (each ticket line's total, its booking fee
included), glasses (snack lines for 3D glasses) and snacks (every other snack line).
Each category's fee is its base times its rate, rounded half up to the cent, plus any
flat amount per item.
"""

import from core.clock { now }
import from core.tenancy.models { Tenant }
import from core.tenancy.groups { attach_to_tenant }
import from core.tenancy.principal { node_id }
import from core.booking.models { Order }
import from core.payments.ledger { record_entry }
import from core.legal.fee_rule { rule_for, rate_of, today }

glob GLASSES: str = "3d_glasses";

node FeeEntry {
    has tenant_id: str,
        order_id: str,
        kind: str,
        amount_cents: int,
        currency: str,
        channel: str = "",
        rule_scope: str = "",
        rule_version: int = 0,
        reason: str = "",
        created_at: str = "",
        recorded_by: str = "";
}

def _round(cents_times_bp: int) -> int {
    # base * bp / 10000, rounded half up (amounts are never negative here).
    return (cents_times_bp + 5000) // 10000;
}

def bases_of(order: Order) -> dict[str, tuple[int, int]] {
    # category -> (base in cents, items).
    tickets = sum([int(l.get("total_cents", 0)) for l in order.lines]);
    glasses = [
        l
        for l in order.snack_lines
        if l.get("purpose") == GLASSES
    ];
    snacks = [
        l
        for l in order.snack_lines
        if l.get("purpose") != GLASSES
    ];
    return {
        "tickets": (tickets, len(order.lines)),
        "glasses": (
            sum([int(l.get("line_cents", 0)) for l in glasses]),
            sum([int(l.get("quantity", 0)) for l in glasses])
        ),
        "snacks": (
            sum([int(l.get("line_cents", 0)) for l in snacks]),
            sum([int(l.get("quantity", 0)) for l in snacks])
        )
    };
}

def compute_fee(order: Order, channel: str, rule: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    # The fee on `order` sold through `channel` under `rule`, with how it was made.
    rates: dict[str, any] = rule.get("rates") or {};  # jac:ignore[W1037]
    parts: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for (category, (base, items)) in bases_of(order).items() {
        if base <= 0 and items <= 0 {
            continue;
        }
        rate = rate_of(rates, channel, category);
        fee = _round(base * rate["bp"]) + rate["per_unit_cents"] * items;
        parts.append(
            {
                "category": category,
                "base_cents": base,
                "items": items,
                "bp": rate["bp"],
                "per_unit_cents": rate["per_unit_cents"],
                "fee_cents": fee
            }
        );
    }
    return {
        "channel": channel,
        "rule_scope": str(rule.get("scope", "platform")),
        "rule_version": int(rule.get("version", 0)),
        "applies_from": str(rule.get("applies_from", "")),
        "parts": parts,
        "fee_cents": sum([p["fee_cents"] for p in parts])
    };
}

def _entry(
    cinema: Tenant, order: Order, kind: str, amount: int, reason: str, recorded_by: str
) -> FeeEntry {
    detail: dict[str, any] = order.fee_detail;  # jac:ignore[W1037]
    made = FeeEntry(
        tenant_id=node_id(cinema),
        order_id=node_id(order),
        kind=kind,
        amount_cents=amount,
        currency=order.currency,
        channel=str(detail.get("channel", "")),
        rule_scope=str(detail.get("rule_scope", "")),
        rule_version=int(detail.get("rule_version", 0)),
        reason=reason,
        created_at=now().isoformat(),
        recorded_by=recorded_by
    );
    order ++> made;
    attach_to_tenant(made, cinema);
    return made;
}

def charge_fee(cinema: Tenant, order: Order, recorded_by: str) -> FeeEntry {
    # Freezes the fee on a paid order and records it. Call as the cinema's principal,
    # inside the commit that confirms it.
    channel = "counter" if recorded_by else "online";
    detail = compute_fee(order, channel, rule_for(node_id(cinema), today()));
    order.fee_cents = detail["fee_cents"];
    order.fee_detail = detail;
    return _entry(cinema, order, "fee", detail["fee_cents"], "", recorded_by);
}

def fee_entries(order: Order) -> list[FeeEntry] {
    return [order-->[?:FeeEntry]];
}

def fee_owed(order: Order) -> int {
    # What the order still owes AfriCinemas: its fee less any credits.
    return sum([e.amount_cents for e in fee_entries(order)]);
}

def credit_for(order: Order, refunded_cents: int) -> int {
    # The fee on `refunded_cents` of the order, in proportion to its total, never more
    # than is still owed.
    if order.total_cents <= 0 or refunded_cents <= 0 {
        return 0;
    }
    share = min(refunded_cents, order.total_cents);
    credit = (order.fee_cents * share * 2 + order.total_cents)
        // (2 * order.total_cents);
    return min(credit, max(fee_owed(order), 0));
}

def record_refund(
    cinema: Tenant,
    order: Order,
    amount_cents: int,
    method: str,
    platform_failure: bool,
    reason: str,
    recorded_by: str
) -> dict[str, int] {
    # A refund to the customer: a "refund" in the money ledger and, for an M-Pesa
    # refund or a Platform failure, the fee on it credited. Call as the cinema's
    # principal, inside the commit that records the refund.
    if amount_cents <= 0 {
        raise ValueError("a refund is a positive amount");
    }
    paid_back = record_entry(cinema, order, "", "refund", 0 - amount_cents, "", reason);
    paid_back.method = method;
    paid_back.recorded_by = recorded_by;
    credited = 0;
    if method == "mpesa" or platform_failure {
        credited = credit_for(order, amount_cents);
        if credited > 0 {
            _entry(
                cinema,
                order,
                "fee_credit",
                0 - credited,
                "platform_failure" if platform_failure else "mpesa_refund",
                recorded_by
            );
        }
    }
    return {"refunded_cents": amount_cents, "fee_credited_cents": credited};
}
