"""Statements and invoices: the back office's Billing page, the console's, and the job
(P15.4, ADR-0083).

- billing(tenant): the cinema's statements, newest first, with how to pay. Staff who
  read the cinema's financial reports (financial_reports.read: owners, general and
  finance managers, auditors).
- billing_pdf(tenant, number): one statement and invoice as a PDF (base64).
- platform_billing(): every cinema's, for platform staff (platform.read), and
  platform_billing_pdf(number).
- platform_issue_statements(): a super admin (platform.settings) issues what's due now,
  in case the job missed it; in the platform audit log. Test runs (AFRICINEMAS_BILLING_EARLY)
  bill the month so far, so the browser tests have a statement to read.
- issue_statements: the job, every BILLING_SECONDS on every server copy.
"""

import os;
import base64;
import from datetime { date }
import from core.clock { now }
import from core.authz.context { resolve_context }
import from core.authz.policy { Resource, require }
import from core.catalog.answers { Refused, answer }
import from core.audit.log { platform_audited }
import from core.tenancy.open_cinema { tenant_by_id }
import from core.platform.staff_api { require_platform }
import from core.platform.cinemas_api { all_cinemas }
import from core.billing.pdf { PdfLine, pdf_bytes }
import from core.billing.statements {
    Statement,
    statements_of,
    statement_numbered,
    tenant_of_number,
    issue_due,
    view_of,
    paybill,
    paybill_is_placeholder,
    DUE_DAYS,
    EARLY_ENV
}

glob READ: str = "financial_reports.read",
     BILLING_SECONDS: int = int(os.environ.get("AFRICINEMAS_BILLING_SECONDS", "3600")),
     MONTHS: list[str] = [
         "January",
         "February",
         "March",
         "April",
         "May",
         "June",
         "July",
         "August",
         "September",
         "October",
         "November",
         "December"
     ],
     CHANNELS: dict[str, str] = {
         "online": "Online",
         "counter_mpesa": "Box office, M-Pesa",
         "counter_cash": "Box office, cash"
     };

def kes(cents: int) -> str {
    sign = "-" if cents < 0 else "";
    return f"{sign}KES {abs(cents) // 100:,}.{abs(cents) % 100:02d}";
}

def _day(iso: str) -> str {
    found = date.fromisoformat(iso[:10]);
    return f"{found.day} {MONTHS[found.month - 1][:3]} {found.year}";
}

def month_label(month: str) -> str {
    return f"{MONTHS[int(month[5:7]) - 1]} {month[:4]}";
}

def statement_pdf(s: Statement) -> bytes {
    f = s.figures;
    lines: list[PdfLine] = [
        PdfLine(text="AfriCinemas", size=18, bold=True),
        PdfLine(text=f"Statement and invoice {s.number}", size=13, bold=True, gap=4),
        PdfLine(
            text=f"{month_label(s.month)}: {_day(s.first)} to {_day(s.last)}", gap=6
        ),
        PdfLine(text=f"For: {s.business_name or s.cinema_name}"),
        PdfLine(text=f"Cinema: {s.cinema_name}" if s.business_name else ""),
        PdfLine(text=f"Issued {_day(s.issued_on)}. Due {_day(s.due_on)}."),
        PdfLine(text="Your takings", bold=True, size=12, gap=10)
    ];
    def row(label: str, cents: int, bold: bool = False) -> PdfLine {
        return PdfLine(text=label, bold=bold, nums=[(kes(cents), 545.0)]);
    }
    lines.append(PdfLine(text="Bookings", nums=[(str(f["bookings"]), 545.0)]));
    lines.append(row("Online", f["online_cents"]));
    lines.append(row("Box office, M-Pesa", f["counter_mpesa_cents"]));
    lines.append(row("Box office, cash", f["counter_cash_cents"]));
    lines.append(row("Gross takings", f["gross_cents"], True));
    lines.append(row("Refunds", 0 - f["refunds_cents"]));
    lines.append(row("Net takings", f["net_cents"], True));
    lines.append(PdfLine(text="AfriCinemas' fees", bold=True, size=12, gap=10));
    lines.append(row("Fees charged", f["fees_charged_cents"]));
    lines.append(row("Fees credited on refunds", 0 - f["fees_credited_cents"]));
    lines.append(row("Fees this month", f["fees_cents"], True));
    if f["brought_forward_cents"] {
        lines.append(row("Credit brought forward", f["brought_forward_cents"]));
    }
    if s.vat_bp {
        lines.append(row(f"VAT at {s.vat_bp // 100}%", f["vat_cents"]));
    }
    lines.append(row("Amount due", f["due_cents"], True));
    if f["carried_forward_cents"] {
        lines.append(row("Credit carried to next month", f["carried_forward_cents"]));
    }
    lines.append(PdfLine(text="How to pay", bold=True, size=12, gap=10));
    lines.append(
        PdfLine(
            text=f"M-Pesa Paybill {s.paybill}, account number {s.number}, by {_day(
                s.due_on
            )}."
        )
    );
    if not s.vat_bp {
        lines.append(PdfLine(text="No VAT: AfriCinemas isn't registered for VAT yet."));
    }
    lines.append(PdfLine(text="Orders", bold=True, size=12, gap=10));
    head = PdfLine(
        text="Reference",
        bold=True,
        size=9,
        cols=[("Date", 150.0), ("Channel", 225.0)],
        nums=[("Paid", 405.0), ("Refunded", 475.0), ("Fee", 545.0)]
    );
    lines.append(head);
    for l in s.lines {
        lines.append(
            PdfLine(
                text=str(l["reference"]),
                size=9,
                cols=[
                    (_day(str(l["at"])), 150.0),
                    (CHANNELS.get(str(l["channel"]), ""), 225.0)
                ],
                nums=[
                    (kes(int(l["paid_cents"])), 405.0),
                    (kes(int(l["refunded_cents"])), 475.0),
                    (kes(int(l["fee_cents"])), 545.0)
                ]
            )
        );
    }
    if not s.lines {
        lines.append(PdfLine(text="No orders this month.", size=9));
    }
    return pdf_bytes(lines, f"AfriCinemas {s.number}");
}

def _pdf_answer(s: Statement) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "ok": True,
        "filename": f"AfriCinemas-{s.number}-{s.month}.pdf",
        "pdf": base64.b64encode(statement_pdf(s)).decode("ascii")
    };
}

def _scope(tenant: str) -> any {  # jac:ignore[W1037]
    scope = resolve_context(tenant);
    require(scope.ctx, READ, Resource(tenant_id=scope.ctx.tenant_id));
    return scope;
}

def _billing(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    cinema = _scope(tenant).tenant;
    return {
        "ok": True,
        "paybill": paybill(),
        "paybill_is_placeholder": paybill_is_placeholder(),
        "due_days": DUE_DAYS,
        "statements": [view_of(s) for s in statements_of(cinema)]
    };
}

def _billing_pdf(tenant: str, number: str) -> dict[str, any] {  # jac:ignore[W1037]
    found = statement_numbered(_scope(tenant).tenant, str(number));
    if found is None {
        raise Refused("not_found", "There's no statement with that number.");
    }
    return _pdf_answer(found);
}

def _platform_billing -> dict[str, any] {  # jac:ignore[W1037]
    require_platform("platform.read");
    rows: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for cinema in all_cinemas() {
        for s in statements_of(cinema) {
            shown = view_of(s, False);
            shown["slug"] = cinema.slug;
            rows.append(shown);
        }
    }
    return {
        "ok": True,
        "paybill": paybill(),
        "paybill_is_placeholder": paybill_is_placeholder(),
        "statements": sorted(
            rows,
            key=lambda (r: dict[str, any]) -> str { return str(r["number"]); },  # jac:ignore[W1037]
            reverse=True
        )
    };
}

def _platform_billing_pdf(number: str) -> dict[str, any] {  # jac:ignore[W1037]
    require_platform("platform.read");
    tenant_id = tenant_of_number(str(number));
    cinema = tenant_by_id(tenant_id) if tenant_id else None;
    found = statement_numbered(cinema, str(number)) if cinema is not None else None;
    if found is None {
        raise Refused("not_found", "There's no statement with that number.");
    }
    return _pdf_answer(found);
}

def:protect billing(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _billing(tenant); });  # jac:ignore[W1037]
}

def:protect billing_pdf(tenant: str, number: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _billing_pdf(tenant, number); });  # jac:ignore[W1037]
}

def:protect platform_billing -> dict[str, any] {  # jac:ignore[W1037]
    return answer(_platform_billing);
}

def:protect platform_billing_pdf(number: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _platform_billing_pdf(number); });  # jac:ignore[W1037]
}

def:protect platform_issue_statements -> dict[str, any] {  # jac:ignore[W1037]
    try {
        me = require_platform("platform.settings");
    } except Refused as e {
        return {"ok": False, "error": {"code": e.code, "message": e.message}};
    }
    early = os.environ.get(EARLY_ENV) == "1";
    return platform_audited(
        me.root_id,
        me.email,
        "platform.statements_issued",
        "billing",
        "statements",
        lambda -> any { return {  # jac:ignore[W1037]
            "ok": True,
            "issued": issue_due(all_cinemas(), now(), early)
        }; }
    );
}

@schedule(trigger=ScheduleTrigger.STATIC, interval=BILLING_SECONDS)
def issue_statements {
    # Runs as Jac's system identity on every server copy; each month is claimed.
    made = issue_due(all_cinemas(), now());
    if made {
        print(f"billing: issued {made}");
    }
}
