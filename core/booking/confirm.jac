"""Confirming a paid order (P5.4, P6.5): one commit makes it confirmed, its seats sold,
its tickets issued and the money a ledger entry; then its link and email follow.

M-Pesa settlement (core/payments/settlement.jac) and a cash sale at the box office
(core/booking/counter_api.jac) both confirm through confirm_order, so a ticket is issued
the same way however it was paid for. The caller passes its own writes (`also`), such
as the M-Pesa payment's new state, to land in the same commit. Each ticket's reference
is claimed for it before the commit and made permanent after it (ADR-0020); the ticket
link likewise (ADR-0022).
"""

import from core.clock { now }
import from core.claims { make_permanent }
import from core.tenancy.models { Tenant }
import from core.tenancy.groups { attach_to_tenant }
import from core.tenancy.principal {
    node_id,
    act_as,
    restore,
    commit_now,
    fresh_node_id,
    assign_id
}
import from core.catalog.models { SeatSlot }
import from core.catalog.venues { find_screening, slots_of }
import from core.booking.models { Order, SeatHold, Ticket }
import from core.booking.availability { SeatState }
import from core.booking.ticket_codes { REFS, reserve_reference, qr_payload }
import from core.booking.ticket_delivery { claim_link, keep_link, queue_mail }
import from core.payments.ledger { record_entry }

glob PROVISIONAL_SECONDS: int = 60;

obj Takings {
    # The money that paid for an order, as its ledger entry records it.
    has payment_id: str,
        amount_cents: int,
        receipt: str,
        note: str,
        method: str,
        recorded_by: str = "";
}

def confirm_order(cinema: Tenant, order: Order, takings: Takings, also: any = None) {  # jac:ignore[W1037]
    # Paid and confirmed, in one commit: the order, its hold, its seats (sold), its
    # tickets and the ledger entry, plus `also()` if given (run as the cinema's
    # principal, before the commit).
    screening = find_screening(cinema, order.screening_id);
    slots: list[SeatSlot] = slots_of(cinema, screening)
        if screening is not None
        else [];
    stamp = now().isoformat();
    # Each ticket's id and reference first: the reference is claimed for its ticket
    # (provisionally, until the commit) and signed into the QR (P6.1).
    tenant_id = node_id(cinema);
    codes: list[list[str]] = [];
    for _ in order.lines {
        ticket_id = fresh_node_id();
        owner = f"{tenant_id}|{ticket_id}";
        reference = reserve_reference(owner, PROVISIONAL_SECONDS);
        codes.append([ticket_id, owner, reference, qr_payload(reference)]);
    }
    claim_link(cinema, order, PROVISIONAL_SECONDS);
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        if also is not None {
            also();
        }
        order.status = "confirmed";
        hold: any = jobj(order.hold_id);  # jac:ignore[W1037]
        if isinstance(hold, SeatHold) {
            (hold as SeatHold).status = "paid";
        }
        for x in slots {
            if x.hold_id == order.hold_id
                and x.state == SeatState.PAYMENT_PENDING.value {
                x.state = SeatState.SOLD.value;
            }
        }
        recorded = record_entry(
            cinema,
            order,
            takings.payment_id,
            "payment",
            takings.amount_cents,
            takings.receipt,
            takings.note
        );
        recorded.method = takings.method;
        recorded.recorded_by = takings.recorded_by;
        for (line, code) in zip(order.lines, codes) {
            ticket = Ticket(
                tenant_id=tenant_id,
                order_id=node_id(order),
                screening_id=order.screening_id,
                seat_label=str(line["seat_label"]),
                ticket_type=str(line["ticket_type"]),
                ticket_name=str(line.get("ticket_name", "")),
                reference=code[2],
                qr=code[3],
                issued_at=stamp
            );
            assign_id(ticket, code[0]);
            order ++> ticket;
            attach_to_tenant(ticket, cinema);
        }
        commit_now();
    } finally {
        restore(me);
    }
    for code in codes {
        make_permanent(REFS, code[2], code[1]);
    }
    # The ticket link for good, and the tickets on their way by email (P6.3).
    keep_link(cinema, order);
    if order.email {
        queue_mail(cinema, order, order.email);
    }
}
