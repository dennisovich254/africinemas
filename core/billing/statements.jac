"""Monthly statements and invoices (P15.4, ADR-0083).

On the 1st of each month, in the cinema's own time zone, every cinema gets a statement
for the month before, with its invoice. Both are one Statement node: the figures and
each order's line are worked out once, when it's issued, and never change. A mistake
is put right by a credit note (later), never by editing. Fee credits for a refund made
after the month (P15.2) are dated when they're given, so they're on the next month's
statement.

What's on it comes from the same ledger entries as the cinema's Reports
(core/reporting/report_api.jac, cinema_records), for the month's local days:
- bookings, and gross takings by channel: online, and the box office's M-Pesa and cash;
- refunds, and the net taken;
- AfriCinemas' fees charged and credited back (core/payments/fees.jac), and what they
  come to;
- what was brought forward: a month whose credits came to more than its fees carries
  that credit to the next statement (one with something on it);
- VAT on the fees at VAT_BP, once AfriCinemas has ticked VAT on the registrations
  checklist (core/legal/registrations.jac), and the amount due.

The invoice number is AC and a sequence (AC000001, AC000002, ...), the account number
for paying it to AfriCinemas' paybill. Each number is a permanent claim, so it's never
given twice or reused; a server stopping in the middle of issuing can leave a gap.
Each cinema's month is claimed too, so it's issued once, however many server copies
run the job. A month with nothing at all on it gets no statement.

The invoice is due DUE_DAYS days after it's issued (owner, 2026-10-28). AfriCinemas'
paybill is a placeholder until it's live (AFRICINEMAS_BILLING_PAYBILL).
"""

import os;
import json;
import uuid;
import from datetime { datetime, date, timedelta }
import from zoneinfo { ZoneInfo }
import from core.clock { now }
import from core.claims { claim, holder, take_claim, release, make_permanent }
import from core.money { BP_PER_WHOLE, div_half_up }
import from core.tenancy.models { Tenant }
import from core.tenancy.groups { attach_to_tenant }
import from core.tenancy.principal { node_id, act_as, restore, flush_now }
import from core.tenancy.verification { record_of }
import from core.catalog.pricing { CURRENCY }
import from core.catalog.storefront_api { cinema_timezone }
import from core.reporting.aggregates { Period, Money, REFUNDS }
import from core.reporting.report_api { cinema_records }

glob DUE_DAYS: int = 5,
     VAT_BP: int = 1600,
     STATEMENT_SPACE: str = "billing-statement",
     NUMBER_SPACE: str = "billing-invoice",
     NEXT: str = "next",
     ISSUING_TTL: int = 600,
     # Nothing to bill that month: its claim says so, and nothing is made.
     NOTHING: str = "nothing",
     PAYBILL_ENV: str = "AFRICINEMAS_BILLING_PAYBILL",
     # Placeholder until AfriCinemas' own paybill is live (owner, 2026-10-28).
     PAYBILL_PLACEHOLDER: str = "000000",
     # Test runs only: the console's Issue now also bills the month in progress.
     EARLY_ENV: str = "AFRICINEMAS_BILLING_EARLY",
     VAT_REGISTRATION: tuple[str, str] = ("legal-registration", "vat");

node Statement {
    # figures: the totals, in cents (see figures_of); lines: one per order, sorted by day.
    has tenant_id: str,
        month: str,
        number: str,
        first: str,
        last: str,
        timezone: str,
        issued_at: str,
        issued_on: str,
        due_on: str,
        currency: str,
        cinema_name: str = "",
        business_name: str = "",
        paybill: str = "",
        vat_bp: int = 0,
        figures: dict[str, int] = {},
        lines: list[dict[str, any]] = [];  # jac:ignore[W1037]
}

def paybill -> str {
    return os.environ.get(PAYBILL_ENV, "").strip() or PAYBILL_PLACEHOLDER;
}

def paybill_is_placeholder -> bool {
    return paybill() == PAYBILL_PLACEHOLDER;
}

def vat_registered -> bool {
    # Whether a super admin has ticked VAT on the registrations checklist.
    (space, key) = VAT_REGISTRATION;
    kept = holder(space, key);
    if not kept {
        return False;
    }
    return bool(json.loads(str(kept)).get("done", False));
}

def month_before(day: date) -> tuple[date, date] {
    # The first and last days of the month before `day`'s.
    last = day.replace(day=1) - timedelta(days=1);
    return (last.replace(day=1), last);
}

def _channel(m: Money) -> str {
    if not m.counter {
        return "online";
    }
    return "counter_cash" if m.method == "cash" else "counter_mpesa";
}

def figures_of(
    money: list[Money], fees: list[Money], brought_forward: int, vat_bp: int
) -> tuple[dict[str, int], list[dict[str, any]]] {  # jac:ignore[W1037]
    # The month's totals and each order's line, from its ledger and fee entries.
    paid = [
        m
        for m in money
        if m.kind == "payment"
    ];
    figures: dict[str, int] = {
        "bookings": len(
            [
                m
                for m in paid
                if m.amount_cents > 0
            ]
        ),
        "online_cents": 0,
        "counter_mpesa_cents": 0,
        "counter_cash_cents": 0
    };
    for m in paid {
        key = _channel(m) + "_cents";
        figures[key] = figures[key] + m.amount_cents;
    }
    figures["gross_cents"] = sum([m.amount_cents for m in paid]);
    figures["refunds_cents"] = -sum(
        [
            m.amount_cents
            for m in money
            if m.kind in REFUNDS
        ]
    );
    figures["net_cents"] = sum([m.amount_cents for m in money]);
    figures["fees_charged_cents"] = sum(
        [
            m.amount_cents
            for m in fees
            if m.kind == "fee"
        ]
    );
    figures["fees_credited_cents"] = -sum(
        [
            m.amount_cents
            for m in fees
            if m.kind == "fee_credit"
        ]
    );
    fees_cents = figures["fees_charged_cents"] - figures["fees_credited_cents"];
    figures["fees_cents"] = fees_cents;
    figures["brought_forward_cents"] = brought_forward;
    owed = fees_cents + brought_forward;
    figures["vat_cents"] = div_half_up(owed * vat_bp, BP_PER_WHOLE) if owed > 0 else 0;
    figures["due_cents"] = max(owed, 0) + figures["vat_cents"];
    figures["carried_forward_cents"] = min(owed, 0);
    by_order: dict[str, dict[str, any]] = {};  # jac:ignore[W1037]
    def line_of(m: Money) -> dict[str, any] {  # jac:ignore[W1037]
        if m.order_ref not in by_order {
            by_order[m.order_ref] = {
                "reference": m.order_ref,
                "at": m.taken_at,
                "channel": "online",
                "paid_cents": 0,
                "refunded_cents": 0,
                "fee_cents": 0
            };
        }
        got = by_order[m.order_ref];
        if m.taken_at < got["at"] {
            got["at"] = m.taken_at;
        }
        return got;
    }
    for m in money {
        got = line_of(m);
        if m.kind == "payment" {
            got["paid_cents"] = got["paid_cents"] + m.amount_cents;
            got["channel"] = _channel(m);
        } elif m.kind in REFUNDS {
            got["refunded_cents"] = got["refunded_cents"] - m.amount_cents;
        }
    }
    for m in fees {
        got = line_of(m);
        got["fee_cents"] = got["fee_cents"] + m.amount_cents;
    }
    lines = sorted(
        by_order.values(),
        key=lambda (l: dict[str, any]) -> tuple[str, str] { return (  # jac:ignore[W1037]
            str(l["at"]),
            str(l["reference"])
        ); }
    );
    return (figures, lines);
}

def statements_of(cinema: Tenant) -> list[Statement] {
    # The cinema's statements, newest month first.
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = [cinema-->[?:Statement]];
    } finally {
        restore(me);
    }
    return sorted(
        found, key=lambda (s: Statement) -> str { return s.month; }, reverse=True
    );
}

def statement_numbered(cinema: Tenant, number: str) -> Statement | None {
    for s in statements_of(cinema) {
        if s.number == number {
            return s;
        }
    }
    return None;
}

def tenant_of_number(number: str) -> str {
    # The cinema an invoice number was given to ("" when none).
    digits = number[2:] if number.startswith("AC") else "";
    if not digits.isdigit() {
        return "";
    }
    held = holder(NUMBER_SPACE, str(int(digits)));
    return held.split("|")[0] if held else "";
}

def _next_number(owner: str) -> str {
    # The next unused number, claimed for `owner` for good. The pointer is only where
    # to start looking: the claim on the number itself is what makes it unique.
    kept = holder(NUMBER_SPACE, NEXT);
    n = int(kept) if kept and kept.isdigit() else 1;
    while claim(NUMBER_SPACE, str(n), owner) != owner {
        n += 1;
    }
    take_claim(NUMBER_SPACE, NEXT);
    claim(NUMBER_SPACE, NEXT, str(n + 1));
    return f"AC{n:06d}";
}

def _local_day(stamp: str, zone: ZoneInfo) -> date | None {
    try {
        return datetime.fromisoformat(stamp).astimezone(zone).date();
    } except ValueError {
        return None;
    }
}

def issue_for(
    cinema: Tenant, at: datetime, month_in_progress: bool = False
) -> Statement | None {
    # The statement for the month before `at` (or, in test runs, the month so far),
    # unless it's been issued, is being issued, or the month has nothing on it.
    timezone = cinema_timezone(cinema);
    zone = ZoneInfo(timezone);
    today = at.astimezone(zone).date();
    (first, last) = (today.replace(day=1), today)
        if month_in_progress
        else month_before(today);
    opened = _local_day(cinema.created_at, zone) if cinema.created_at else None;
    if opened is not None and opened > last {
        return None;
    }
    tenant_id = node_id(cinema);
    month = first.isoformat()[:7];
    key = f"{tenant_id}|{month}";
    owner = f"{key}|{uuid.uuid4().hex}";
    if claim(STATEMENT_SPACE, key, owner, ISSUING_TTL) != owner {
        return None;
    }
    try {
        period = Period(timezone=timezone, first=first, last=last);
        found = cinema_records(cinema);
        money = [
            m
            for m in found.money
            if period.covers(m.taken_at)
        ];
        fees = [
            m
            for m in found.fees
            if period.covers(m.taken_at)
        ];
        before = statements_of(cinema);
        brought = before[0].figures.get("carried_forward_cents", 0) if before else 0;
        # Nothing on it: no statement, and any credit waits for the next one.
        if not money and not fees {
            take_claim(STATEMENT_SPACE, key);
            claim(STATEMENT_SPACE, key, NOTHING);
            return None;
        }
        vat_bp = VAT_BP if vat_registered() else 0;
        (figures, lines) = figures_of(money, fees, brought, vat_bp);
        number = _next_number(owner);
        details = record_of(cinema)["details"];
        me = node_id(root);
        act_as(cinema.principal_root_id);
        try {
            made = Statement(
                tenant_id=tenant_id,
                month=month,
                number=number,
                first=first.isoformat(),
                last=last.isoformat(),
                timezone=timezone,
                issued_at=at.isoformat(),
                issued_on=today.isoformat(),
                due_on=(today + timedelta(days=DUE_DAYS)).isoformat(),
                currency=CURRENCY,
                cinema_name=cinema.name,
                business_name=str(details.get("registered_name", "")),
                paybill=paybill(),
                vat_bp=vat_bp,
                figures=figures,
                lines=lines
            );
            cinema ++> made;
            attach_to_tenant(made, cinema);
            flush_now();
        } finally {
            restore(me);
        }
    } except Exception as e {
        release(STATEMENT_SPACE, key, owner);
        raise e;
    }
    make_permanent(STATEMENT_SPACE, key, owner);
    return made;
}

def issue_due(
    cinemas: list[Tenant], at: datetime, month_in_progress: bool = False
) -> list[str] {
    # Issues every statement due as of `at`; the invoice numbers made.
    made: list[str] = [];
    for cinema in cinemas {
        try {
            got = issue_for(cinema, at, month_in_progress);
        } except Exception as e {
            print(f"billing: {cinema.slug}'s statement failed: {e}");
            continue;
        }
        if got is not None {
            made.append(got.number);
        }
    }
    return made;
}

def view_of(s: Statement, with_lines: bool = True) -> dict[str, any] {  # jac:ignore[W1037]
    shown: dict[str, any] = {  # jac:ignore[W1037]
        "number": s.number,
        "month": s.month,
        "first": s.first,
        "last": s.last,
        "issued_on": s.issued_on,
        "due_on": s.due_on,
        "currency": s.currency,
        "cinema_name": s.cinema_name,
        "business_name": s.business_name,
        "paybill": s.paybill,
        "paybill_is_placeholder": s.paybill == PAYBILL_PLACEHOLDER,
        "vat_bp": s.vat_bp,
        "figures": dict(s.figures)
    };
    if with_lines {
        shown["lines"] = [dict(l) for l in s.lines];
    }
    return shown;
}
