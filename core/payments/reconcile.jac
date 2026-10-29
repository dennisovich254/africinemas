"""Reconciliation (P15.6, ADR-0085): our records checked against M-Pesa's and the cash.

Owner's decisions (2026-10-28): no extra Daraja credentials. Three checks, each turning
what doesn't add up into an **exception** for the cinema and the console:

1. **Every day, M-Pesa is asked again** about each payment of the last LOOKBACK_DAYS, with
   the account it was made with (provider_of), once per payment it answers about (one
   it doesn't know, or hasn't answered yet, is asked again next time):
   - `not_paid`: we sold on it, but M-Pesa says it wasn't paid;
   - `no_order`: M-Pesa says it was paid, but nothing was sold for it;
   - `amount_differs`: M-Pesa's amount isn't ours.
   And every receipt is on one payment only (`receipt_twice`).
2. **An M-Pesa statement the cinema uploads** (the CSV from Safaricom's M-Pesa portal)
   is matched line by line, by receipt, for the time it covers:
   - `not_in_app`: money reached the paybill that no order of ours took (paid at the
     paybill by hand, for example). The KES 1 test payments (account TEST) are skipped;
   - `not_in_statement`: an M-Pesa payment of ours the statement doesn't have;
   - `amount_differs`.
3. **A cash-up** at the box office: the cash counted against the cash sales (less cash
   refunds) recorded by that member of staff since their last cash-up. Any
   difference is `cash_short` or `cash_over`.

Each exception is kept once (a claim on its kind and what it's about), so checks that
run again add nothing. Staff who read the reports mark one resolved with a note; it
stays listed, resolved.
"""

import os;
import csv;
import io;
import from datetime { datetime, timedelta }
import from zoneinfo { ZoneInfo }
import from core.clock { now }
import from core.claims { claim, release }
import from core.catalog.answers { Refused }
import from core.tenancy.models { Tenant }
import from core.tenancy.groups { attach_to_tenant }
import from core.tenancy.principal {
    node_id,
    act_as,
    restore,
    flush_now,
    fresh_node_id
}
import from core.catalog.models { Venue, Auditorium, Screening }
import from core.booking.models { Order }
import from core.payments.models { PaymentIntent }
import from core.payments.ledger { LedgerEntry }
import from core.payments.state { PaymentState }
import from core.payments.payment_api { provider_of }
import from core.money { cents_of_shillings }

glob LOOKBACK_DAYS: int = 3,
     CHECKED: str = "recon-checked",
     KEPT: str = "recon-exception",
     REFUNDS: list[str] = ["refund", "refund_due", "reversal"],
     STATEMENT_MAX_ROWS: int = 20000,
     NOTE_MAX: int = 500,
     RECON_SECONDS: int = int(os.environ.get("AFRICINEMAS_RECON_SECONDS", "21600")),
     LABELS: dict[str, str] = {
         "not_paid": "Sold, but M-Pesa says it wasn't paid",
         "no_order": "Paid on M-Pesa, but nothing was sold",
         "amount_differs": "M-Pesa's amount isn't ours",
         "receipt_twice": "One M-Pesa receipt on two payments",
         "not_in_app": "On the M-Pesa statement, but no order took it",
         "not_in_statement": "Our M-Pesa payment isn't on the statement",
         "cash_short": "Cash short at a cash-up",
         "cash_over": "Cash over at a cash-up"
     };

node ReconException {
    # One thing that doesn't add up. source: "mpesa" (the daily check), "statement" or
    # "cash_up". expected_cents is ours, found_cents the other side's.
    has tenant_id: str,
        kind: str,
        source: str,
        reference: str = "",
        receipt: str = "",
        expected_cents: int = 0,
        found_cents: int = 0,
        detail: str = "",
        found_at: str = "",
        status: str = "open",
        resolved_by: str = "",
        resolved_at: str = "",
        resolved_note: str = "";
}

node CashUp {
    # A member of staff's count: what they counted, what they'd recorded, since when.
    has tenant_id: str,
        member_id: str,
        member: str,
        counted_cents: int,
        expected_cents: int,
        since: str,
        at: str;
}

def exception_view(e: ReconException) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "exception_id": node_id(e),
        "kind": e.kind,
        "label": LABELS.get(e.kind, e.kind),
        "source": e.source,
        "reference": e.reference,
        "receipt": e.receipt,
        "expected_cents": e.expected_cents,
        "found_cents": e.found_cents,
        "detail": e.detail,
        "found_at": e.found_at,
        "status": e.status,
        "resolved_by": e.resolved_by,
        "resolved_at": e.resolved_at,
        "resolved_note": e.resolved_note
    };
}

def _as_cinema(cinema: Tenant, work: any) -> any {  # jac:ignore[W1037]
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        return work();
    } finally {
        restore(me);
    }
}

def exceptions_of(cinema: Tenant) -> list[ReconException] {
    found = _as_cinema(cinema, lambda -> any { return [cinema-->[?:ReconException]]; });  # jac:ignore[W1037]
    return sorted(
        found,
        key=lambda (e: ReconException) -> str { return e.found_at; },
        reverse=True
    );
}

def keep(  # jac:ignore[W3030] the exception: whose, what, why, about what, the amounts
    cinema: Tenant,
    kind: str,
    source: str,
    about: str,
    reference: str = "",
    receipt: str = "",
    expected: int = 0,
    found: int = 0,
    detail: str = ""
) -> bool {
    # Records the exception unless it's already kept (the same kind, about the same
    # thing); True when it's new.
    mine = fresh_node_id();
    if claim(KEPT, f"{node_id(cinema)}|{kind}|{about}", mine) != mine {
        return False;
    }
    def made -> any {  # jac:ignore[W1037]
        e = ReconException(
            tenant_id=node_id(cinema),
            kind=kind,
            source=source,
            reference=reference,
            receipt=receipt,
            expected_cents=expected,
            found_cents=found,
            detail=detail,
            found_at=now().isoformat()
        );
        cinema ++> e;
        attach_to_tenant(e, cinema);
        flush_now();
        return e;
    }
    _as_cinema(cinema, made);
    return True;
}

def resolve(cinema: Tenant, exception_id: str, note: str, who: str) -> ReconException {
    clean = " ".join(str(note or "").split());
    if not clean or len(clean) > NOTE_MAX {
        raise Refused(
            "invalid_note",
            f"Say how it was sorted out, in up to {NOTE_MAX} characters."
        );
    }
    found = [
        e
        for e in exceptions_of(cinema)
        if node_id(e) == exception_id
    ];
    if len(found) == 0 {
        raise Refused("not_found", "There's no such exception.");
    }
    e = found[0];
    if e.status != "open" {
        raise Refused("already_resolved", "That's already resolved.");
    }
    def mark -> any {  # jac:ignore[W1037]
        e.status = "resolved";
        e.resolved_by = who;
        e.resolved_at = now().isoformat();
        e.resolved_note = clean;
        flush_now();
        return e;
    }
    _as_cinema(cinema, mark);
    return e;
}

def _orders(cinema: Tenant) -> list[Order] {
    # Every order of the cinema: its showtimes' and its venues' own (snacks only).
    def walk -> any {  # jac:ignore[W1037]
        found: list[Order] = [];
        for venue in [cinema-->[?:Venue]] {
            found.extend([venue-->[?:Order]]);
            for screen in [venue-->[?:Auditorium]] {
                for s in [screen-->[?:Screening]] {
                    found.extend([s-->[?:Order]]);
                }
            }
        }
        return found;
    }
    return _as_cinema(cinema, walk);
}

def _records(
    cinema: Tenant
) -> list[tuple[Order, list[PaymentIntent], list[LedgerEntry]]] {
    def read -> any {  # jac:ignore[W1037]
        return [
            (o, [o-->[?:PaymentIntent]], [o-->[?:LedgerEntry]]) for o in _orders(cinema)
        ];
    }
    return _as_cinema(cinema, read);
}

def _recent(stamp: str, since: datetime) -> bool {
    if not stamp {
        return False;
    }
    try {
        return datetime.fromisoformat(stamp) >= since;
    } except ValueError {
        return False;
    }
}

def check_mpesa(cinema: Tenant, at: datetime) -> int {
    # The daily check: M-Pesa asked again about each recent payment; how many new
    # exceptions.
    since = at - timedelta(days=LOOKBACK_DAYS);
    made = 0;
    receipts: dict[str, list[str]] = {};
    for (order, intents, entries) in _records(cinema) {
        sold = {
            e.intent_id: e
            for e in entries
            if e.kind == "payment" and e.method == "mpesa" and e.amount_cents > 0
        };
        for e in sold.values() {
            if e.receipt {
                receipts.setdefault(e.receipt, []).append(order.reference);
            }
        }
        for intent in intents {
            if not intent.checkout_request_id
                or not _recent(intent.updated_at, since) {
                continue;
            }
            if intent.state
                not in [
                    "success",
                    "failed",
                    "cancelled",
                    "timeout",
                    "needs_attention"
                ] {
                continue;
            }
            ref = intent.reference;
            if claim(CHECKED, f"{node_id(cinema)}|{ref}", "1") != "1" {
                continue;
            }
            provider = provider_of(cinema, intent);
            if provider is None {
                continue;
            }
            status = provider.query(intent.checkout_request_id);
            # No answer yet, or M-Pesa doesn't know it (a prompt too old to ask about):
            # unchecked, so asked again next time while it's still recent.
            if status.state in [PaymentState.UNKNOWN, PaymentState.STK_REQUESTED] {
                release(CHECKED, f"{node_id(cinema)}|{ref}", "1");
                continue;
            }
            taken = sold.get(node_id(intent));
            paid = status.state == PaymentState.SUCCESS;
            if taken is not None and not paid {
                made += int(
                    keep(
                        cinema,
                        "not_paid",
                        "mpesa",
                        ref,
                        order.reference,
                        taken.receipt,
                        taken.amount_cents,
                        0,
                        status.result_text
                    )
                );
            } elif taken is None and paid {
                made += int(
                    keep(
                        cinema,
                        "no_order",
                        "mpesa",
                        ref,
                        order.reference,
                        status.receipt,
                        0,
                        status.amount_cents,
                        intent.attention_reason
                    )
                );
            } elif taken is not None
                and paid
                and status.amount_cents
                and status.amount_cents != taken.amount_cents {
                made += int(
                    keep(
                        cinema,
                        "amount_differs",
                        "mpesa",
                        ref,
                        order.reference,
                        status.receipt,
                        taken.amount_cents,
                        status.amount_cents
                    )
                );
            }
        }
    }
    for (receipt, refs) in receipts.items() {
        if len(refs) > 1 {
            made += int(
                keep(
                    cinema,
                    "receipt_twice",
                    "mpesa",
                    receipt,
                    ", ".join(sorted(refs)),
                    receipt,
                    0,
                    0,
                    f"{len(refs)} payments"
                )
            );
        }
    }
    return made;
}

def check_all(cinemas: list[Tenant], at: datetime) -> int {
    made = 0;
    for cinema in cinemas {
        try {
            made += check_mpesa(cinema, at);
        } except Exception as e {
            print(f"reconcile: {cinema.slug} failed: {e}");
        }
    }
    return made;
}

def column_of(header: list[str], names: list[str]) -> int {
    tidy = [h.strip().lower().replace(".", "").replace("/", "") for h in header];
    for name in names {
        if name in tidy {
            return tidy.index(name);
        }
    }
    return -1;
}

def time_of(text: str) -> datetime | None {
    # M-Pesa portal times: "2026-10-28 14:03:22" (local Nairobi), or ISO.
    for fmt in [
        "%Y-%m-%d %H:%M:%S",
        "%d-%m-%Y %H:%M:%S",
        "%d/%m/%Y %H:%M:%S",
        "%Y-%m-%dT%H:%M:%S"
    ] {
        try {
            return datetime.strptime(text.strip()[:19], fmt);
        } except ValueError {
            continue;
        }
    }
    return None;
}

def match_statement(cinema: Tenant, text: str, timezone: str) -> dict[str, int] {
    # Matches an M-Pesa statement (CSV) against our M-Pesa payments for the time it
    # covers: {"rows", "matched", "exceptions"}.
    rows = list(csv.reader(io.StringIO(text)));
    header_at = -1;
    for (n, row) in enumerate(rows[:30]) {
        if column_of(row, ["receipt no", "receipt"]) >= 0
            and column_of(row, ["paid in"]) >= 0 {
            header_at = n;
            break;
        }
    }
    if header_at < 0 {
        raise Refused(
            "not_a_statement",
            "That isn't an M-Pesa statement: it needs Receipt No., Completion Time and Paid In columns."
        );
    }
    header = rows[header_at];
    receipt_col = column_of(header, ["receipt no", "receipt"]);
    time_col = column_of(header, ["completion time", "completed", "transaction time"]);
    paid_col = column_of(header, ["paid in"]);
    status_col = column_of(header, ["transaction status", "status"]);
    account_col = column_of(header, ["ac no", "account no", "account"]);
    if time_col < 0 {
        raise Refused(
            "not_a_statement", "The statement needs its Completion Time column."
        );
    }
    body = rows[header_at + 1:];
    if len(body) > STATEMENT_MAX_ROWS {
        raise Refused(
            "too_long", f"Upload at most {STATEMENT_MAX_ROWS} lines at a time."
        );
    }
    zone = ZoneInfo(timezone);
    theirs: dict[str, tuple[int, datetime]] = {};
    for row in body {
        if len(row) <= max(receipt_col, time_col, paid_col) {
            continue;
        }
        receipt = row[receipt_col].strip();
        when = time_of(row[time_col]);
        paid = cents_of_shillings(row[paid_col].replace(",", "").strip() or "0");
        if not receipt or when is None or paid is None or paid <= 0 {
            continue;
        }
        if status_col >= 0
            and row[status_col].strip().lower() not in ["completed", ""] {
            continue;
        }
        if account_col >= 0 and row[account_col].strip().upper() == "TEST" {
            continue;
        }
        theirs[receipt] = (paid, when.replace(tzinfo=zone));
    }
    if len(theirs) == 0 {
        raise Refused("empty_statement", "The statement has no payments in.");
    }
    first = min([w for (_, w) in theirs.values()]);
    last = max([w for (_, w) in theirs.values()]);
    ours: dict[str, tuple[int, str]] = {};
    for (order, _, entries) in _records(cinema) {
        for e in entries {
            if e.kind == "payment"
                and e.method == "mpesa"
                and e.receipt
                and e.amount_cents > 0 {
                ours[e.receipt] = (e.amount_cents, order.reference);
                if not (first <= datetime.fromisoformat(e.created_at) <= last) {
                    ours[e.receipt] = (e.amount_cents, "outside:" + order.reference);
                }
            }
        }
    }
    made = 0;
    matched = 0;
    for (receipt, (paid, when)) in theirs.items() {
        if receipt not in ours {
            made += int(
                keep(
                    cinema,
                    "not_in_app",
                    "statement",
                    receipt,
                    "",
                    receipt,
                    0,
                    paid,
                    when.isoformat()
                )
            );
            continue;
        }
        (amount, reference) = ours[receipt];
        reference = reference.replace("outside:", "");
        if amount != paid {
            made += int(
                keep(
                    cinema,
                    "amount_differs",
                    "statement",
                    receipt,
                    reference,
                    receipt,
                    amount,
                    paid
                )
            );
        } else {
            matched += 1;
        }
    }
    for (receipt, (amount, reference)) in ours.items() {
        if receipt not in theirs and not reference.startswith("outside:") {
            made += int(
                keep(
                    cinema,
                    "not_in_statement",
                    "statement",
                    receipt,
                    reference,
                    receipt,
                    amount,
                    0
                )
            );
        }
    }
    return {"rows": len(theirs), "matched": matched, "exceptions": made};
}

def cash_ups_of(cinema: Tenant) -> list[CashUp] {
    found = _as_cinema(cinema, lambda -> any { return [cinema-->[?:CashUp]]; });  # jac:ignore[W1037]
    return sorted(found, key=lambda (c: CashUp) -> str { return c.at; }, reverse=True);
}

def cash_up(cinema: Tenant, member_id: str, member: str, counted: int) -> CashUp {
    # The member's count against the cash they recorded since their last cash-up.
    if not isinstance(counted, int) or counted < 0 {
        raise Refused("invalid_amount", "Enter the cash you counted, in shillings.");
    }
    mine = [
        c
        for c in cash_ups_of(cinema)
        if c.member_id == member_id
    ];
    since = mine[0].at if mine else "";
    expected = 0;
    for (_, _, entries) in _records(cinema) {
        for e in entries {
            if e.recorded_by != member_id or e.method != "cash" {
                continue;
            }
            if since and e.created_at <= since {
                continue;
            }
            if e.kind == "payment" or e.kind in REFUNDS {
                expected += e.amount_cents;
            }
        }
    }
    at = now().isoformat();
    def made -> any {  # jac:ignore[W1037]
        c = CashUp(
            tenant_id=node_id(cinema),
            member_id=member_id,
            member=member,
            counted_cents=counted,
            expected_cents=expected,
            since=since,
            at=at
        );
        cinema ++> c;
        attach_to_tenant(c, cinema);
        flush_now();
        return c;
    }
    done = _as_cinema(cinema, made);
    if counted != expected {
        keep(
            cinema,
            "cash_short" if counted < expected else "cash_over",
            "cash_up",
            f"{member_id}|{at}",
            "",
            "",
            expected,
            counted,
            member
        );
    }
    return done;
}

def cash_up_view(c: CashUp) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "member": c.member,
        "counted_cents": c.counted_cents,
        "expected_cents": c.expected_cents,
        "difference_cents": c.counted_cents - c.expected_cents,
        "since": c.since,
        "at": c.at
    };
}
