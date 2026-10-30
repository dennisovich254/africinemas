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
import from core.audit.log { audited, platform_audited }
import from core.tenancy.open_cinema { tenant_by_id }
import from core.platform.staff_api { require_platform }
import from core.platform.cinemas_api { all_cinemas }
import from core.billing.pdf { PdfLine, pdf_bytes }
import from core.billing.billing_text { kes, day_label, month_label }
import from core.billing.collect {
    start_payment,
    settle,
    payment_named,
    payments_of,
    payment_view,
    unmatched_payments,
    resolve_payment,
    remind_due,
    queue_mail
}
import from core.billing.suspension { set_suspension }
import from core.support.requests { file_request }
import from core.tenancy.models { Tenant }
import from core.tenancy.registry { lookup_slug }
import from core.tenancy.principal { node_id }
import from core.billing.statements {
    Statement,
    statements_of,
    statement_numbered,
    tenant_of_number,
    issue_due,
    view_of,
    paybill,
    paybill_is_placeholder,
    payable_of,
    status_of,
    days_overdue,
    disputed,
    update_statement,
    local_today,
    DUE_DAYS,
    GRACE_DAYS,
    EARLY_ENV
}
import from core.platform.jobs { ran }

glob READ: str = "financial_reports.read",
     DISPUTE_MAX: int = 1000,
     BILLING_SECONDS: int = int(os.environ.get("AFRICINEMAS_BILLING_SECONDS", "3600")),
     CHANNELS: dict[str, str] = {
         "online": "Online",
         "counter_mpesa": "Box office, M-Pesa",
         "counter_cash": "Box office, cash"
     };

def statement_pdf(s: Statement) -> bytes {
    f = s.figures;
    lines: list[PdfLine] = [
        PdfLine(text="AfriCinemas", size=18, bold=True),
        PdfLine(text=f"Statement and invoice {s.number}", size=13, bold=True, gap=4),
        PdfLine(
            text=f"{month_label(s.month)}: {day_label(s.first)} to {day_label(s.last)}",
            gap=6
        ),
        PdfLine(text=f"For: {s.business_name or s.cinema_name}"),
        PdfLine(text=f"Cinema: {s.cinema_name}" if s.business_name else ""),
        PdfLine(text=f"Issued {day_label(s.issued_on)}. Due {day_label(s.due_on)}."),
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
    if f.get("rounding_cents", 0) {
        lines.append(row("Rounded to whole shillings for M-Pesa", f["rounding_cents"]));
        lines.append(row("To pay", f["payable_cents"], True));
    }
    lines.append(PdfLine(text="How to pay", bold=True, size=12, gap=10));
    lines.append(
        PdfLine(
            text=f"By {day_label(
                s.due_on
            )}, from your Billing page: Pay now sends an M-Pesa prompt for {kes(
                payable_of(s)
            )}"
        )
    );
    lines.append(
        PdfLine(
            text=f"to your phone, to Paybill {s.paybill}, account number {s.number}."
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
                    (day_label(str(l["at"])), 150.0),
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


def _cinema_of_slug(slug: str) -> Tenant {
    tenant_id = lookup_slug(slug) if slug else None;
    cinema = tenant_by_id(str(tenant_id)) if tenant_id else None;
    if cinema is None {
        raise Refused("not_found", "There's no cinema at that address.");
    }
    return cinema;
}

def _statement(cinema: Tenant, number: str) -> Statement {
    found = statement_numbered(cinema, str(number));
    if found is None {
        raise Refused("not_found", "There's no statement with that number.");
    }
    return found;
}

def _billing(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    cinema = _scope(tenant).tenant;
    today = local_today(cinema);
    return {
        "ok": True,
        "paybill": paybill(),
        "paybill_is_placeholder": paybill_is_placeholder(),
        "due_days": DUE_DAYS,
        "today": today.isoformat(),
        "statements": [view_of(s, today) for s in statements_of(cinema)],
        "payments": [payment_view(p) for p in payments_of(cinema)]
    };
}

def _billing_pdf(tenant: str, number: str) -> dict[str, any] {  # jac:ignore[W1037]
    return _pdf_answer(_statement(_scope(tenant).tenant, number));
}

def _pay(tenant: str, number: str, phone: str) -> dict[str, any] {  # jac:ignore[W1037]
    cinema = _scope(tenant).tenant;
    made = start_payment(cinema, _statement(cinema, number), phone, node_id(root));
    return {"ok": True, "payment": payment_view(made)};
}

def _payment(tenant: str, reference: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The payment, settled now when M-Pesa has answered.
    cinema = _scope(tenant).tenant;
    found = payment_named(cinema, str(reference));
    if found is None {
        raise Refused("not_found", "There's no payment with that reference.");
    }
    settle(cinema, found);
    s = statement_numbered(cinema, found.number);
    return {
        "ok": True,
        "payment": payment_view(found),
        "status": status_of(s, local_today(cinema)) if s is not None else ""
    };
}

def _dispute(tenant: str, number: str, text: str) -> dict[str, any] {  # jac:ignore[W1037]
    cinema = _scope(tenant).tenant;
    s = _statement(cinema, number);
    status = status_of(s, local_today(cinema));
    if status not in ["due", "overdue"] {
        raise Refused(
            "nothing_to_dispute", "Only an invoice still to pay can be disputed."
        );
    }
    if disputed(s) {
        raise Refused(
            "already_disputed",
            "You've told us about this invoice already. We'll answer in Help."
        );
    }
    clean = " ".join(str(text or "").split());
    if len(clean) < 10 or len(clean) > DISPUTE_MAX {
        raise Refused(
            "invalid_text",
            f"Say what's wrong with the invoice, in 10 to {DISPUTE_MAX} characters."
        );
    }
    request = file_request(
        cinema,
        "invoice_dispute",
        f"Invoice {s.number} ({month_label(s.month)}): {clean}"
    );
    who = str(request["messages"][0]["by"]);
    update_statement(
        cinema,
        s,
        {
            "disputed_at": now().isoformat(),
            "dispute_text": clean,
            "dispute_by": who,
            "dispute_request_id": request["request_id"],
            "dispute_resolved_at": "",
            "dispute_outcome": "",
            "dispute_note": ""
        }
    );
    return {"ok": True, "request_id": request["request_id"]};
}

def _notice(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    # For every member of the cinema's team: whether it's suspended and why, and its
    # overdue invoices (numbers and days only).
    scope = resolve_context(tenant);
    cinema = scope.tenant;
    may_pay = True;
    try {
        require(scope.ctx, READ, Resource(tenant_id=scope.ctx.tenant_id));
    } except Exception {
        may_pay = False;
    }
    today = local_today(cinema);
    late = [
        {"number": s.number, "due_on": s.due_on, "days": days_overdue(s, today)}
        for s in statements_of(cinema)
        if status_of(s, today) == "overdue"
    ];
    return {
        "ok": True,
        "suspended": cinema.state == "suspended",
        "suspended_reason": cinema.suspended_reason
            if cinema.state == "suspended"
            else "",
        "overdue": late,
        "may_pay": may_pay
    };
}

def _platform_billing -> dict[str, any] {  # jac:ignore[W1037]
    require_platform("platform.read");
    rows: list[dict[str, any]] = [];  # jac:ignore[W1037]
    cinemas = all_cinemas();
    for cinema in cinemas {
        today = local_today(cinema);
        for s in statements_of(cinema) {
            shown = view_of(s, today, False);
            shown["slug"] = cinema.slug;
            shown["cinema_state"] = cinema.state;
            rows.append(shown);
        }
    }
    return {
        "ok": True,
        "paybill": paybill(),
        "paybill_is_placeholder": paybill_is_placeholder(),
        "grace_days": GRACE_DAYS,
        "statements": sorted(
            rows,
            key=lambda (r: dict[str, any]) -> str { return str(r["number"]); },  # jac:ignore[W1037]
            reverse=True
        ),
        "unmatched": unmatched_payments(cinemas)
    };
}

def _platform_billing_pdf(number: str) -> dict[str, any] {  # jac:ignore[W1037]
    require_platform("platform.read");
    tenant_id = tenant_of_number(str(number));
    cinema = tenant_by_id(tenant_id) if tenant_id else None;
    if cinema is None {
        raise Refused("not_found", "There's no statement with that number.");
    }
    return _pdf_answer(_statement(cinema, number));
}

def _invoice_cinema(number: str) -> Tenant {
    tenant_id = tenant_of_number(str(number));
    cinema = tenant_by_id(tenant_id) if tenant_id else None;
    if cinema is None {
        raise Refused("not_found", "There's no invoice with that number.");
    }
    return cinema;
}

def _decide_dispute(number: str, outcome: str, note: str) -> dict[str, any] {  # jac:ignore[W1037]
    cinema = _invoice_cinema(number);
    s = _statement(cinema, number);
    if not disputed(s) {
        raise Refused("not_disputed", "That invoice has no open dispute.");
    }
    if outcome not in ["stands", "waived"] {
        raise Refused(
            "invalid_outcome", "Choose whether the invoice stands or is waived."
        );
    }
    clean = " ".join(str(note or "").split());
    if not clean or len(clean) > DISPUTE_MAX {
        raise Refused("invalid_note", f"Say why, in up to {DISPUTE_MAX} characters.");
    }
    update_statement(
        cinema,
        s,
        {
            "dispute_resolved_at": now().isoformat(),
            "dispute_outcome": outcome,
            "dispute_note": clean
        }
    );
    queue_mail(
        cinema,
        f"{cinema.name}: your query about invoice {s.number}",
        (
            f"We looked at invoice {s.number}: it stands as issued. {clean}"
                if outcome == "stands"
                else f"We looked at invoice {s.number}: there's nothing to pay on it. {clean}"
        )
    );
    return {"ok": True, "statement": view_of(s, local_today(cinema), False)};
}

def _resolve(
    slug: str, reference: str, action: str, number: str, note: str, who: str
) -> dict[str, any] {  # jac:ignore[W1037]
    cinema = _cinema_of_slug(slug);
    found = payment_named(cinema, str(reference));
    if found is None {
        raise Refused("not_found", "There's no payment with that reference.");
    }
    resolve_payment(cinema, found, action, number, note, who);
    return {"ok": True, "payment": payment_view(found)};
}

def _suspend(slug: str, reason: str, who: str) -> dict[str, any] {  # jac:ignore[W1037]
    cinema = _cinema_of_slug(slug);
    if cinema.state != "active" {
        raise Refused("not_active", "Only a live cinema can be suspended.");
    }
    today = local_today(cinema);
    late = [
        s
        for s in statements_of(cinema)
        if view_of(s, today, False)["suspendable"]
    ];
    if len(late) == 0 {
        raise Refused(
            "not_overdue",
            f"A cinema is suspended only with an invoice more than {GRACE_DAYS} days overdue and not disputed."
        );
    }
    clean = " ".join(str(reason or "").split());
    if len(clean) < 5 or len(clean) > DISPUTE_MAX {
        raise Refused(
            "invalid_reason",
            f"Say why, in 5 to {DISPUTE_MAX} characters: the cinema's team sees it."
        );
    }
    set_suspension(cinema, True, clean, who);
    numbers = ", ".join([s.number for s in late]);
    queue_mail(
        cinema,
        f"{cinema.name} is suspended on AfriCinemas",
        f"{cinema.name}'s storefront is down and it can't take bookings or payments: invoice {numbers} is overdue. {clean} Pay it from your Billing page and we'll reinstate the cinema."
    );
    return {"ok": True, "state": cinema.state};
}

def _reinstate(slug: str, who: str) -> dict[str, any] {  # jac:ignore[W1037]
    cinema = _cinema_of_slug(slug);
    if cinema.state != "suspended" {
        raise Refused("not_suspended", "That cinema isn't suspended.");
    }
    set_suspension(cinema, False, "", who);
    queue_mail(
        cinema,
        f"{cinema.name} is back on AfriCinemas",
        f"{cinema.name} is reinstated: its storefront is up and it takes bookings and payments again."
    );
    return {"ok": True, "state": cinema.state};
}

def _refused(e: Refused) -> dict[str, any] {  # jac:ignore[W1037]
    return {"ok": False, "error": {"code": e.code, "message": e.message}};
}

def:protect billing(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _billing(tenant); });  # jac:ignore[W1037]
}

def:protect billing_pdf(tenant: str, number: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _billing_pdf(tenant, number); });  # jac:ignore[W1037]
}

def:protect pay_invoice(tenant: str, number: str, phone: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The amount is the invoice's, never the caller's.
    return audited(
        tenant,
        "billing.payment_started",
        "invoice",
        str(number),
        lambda -> any { return _pay(tenant, number, phone); }  # jac:ignore[W1037]
    );
}

def:protect invoice_payment(tenant: str, reference: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _payment(tenant, reference); });  # jac:ignore[W1037]
}

def:protect dispute_invoice(tenant: str, number: str, text: str) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "billing.disputed",
        "invoice",
        str(number),
        lambda -> any { return _dispute(tenant, number, text); }  # jac:ignore[W1037]
    );
}

def:protect billing_notice(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _notice(tenant); });  # jac:ignore[W1037]
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
        return _refused(e);
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

def:protect platform_decide_dispute(
    number: str, outcome: str, note: str
) -> dict[str, any] {  # jac:ignore[W1037]
    try {
        me = require_platform("platform.settings");
    } except Refused as e {
        return _refused(e);
    }
    return platform_audited(
        me.root_id,
        me.email,
        "platform.dispute_decided",
        "invoice",
        str(number),
        lambda -> any { return _decide_dispute(number, outcome, note); },  # jac:ignore[W1037]
        detail=str(outcome)
    );
}

def:protect platform_resolve_payment(
    slug: str, reference: str, action: str, number: str, note: str
) -> dict[str, any] {  # jac:ignore[W1037]
    try {
        me = require_platform("platform.settings");
    } except Refused as e {
        return _refused(e);
    }
    return platform_audited(
        me.root_id,
        me.email,
        "platform.payment_resolved",
        "bill_payment",
        str(reference),
        lambda -> any { return _resolve(  # jac:ignore[W1037]
            slug, reference, action, number, note, me.email
        ); },
        detail=str(action)
    );
}

def:protect platform_suspend_cinema(slug: str, reason: str) -> dict[str, any] {  # jac:ignore[W1037]
    try {
        me = require_platform("platform.suspend");
    } except Refused as e {
        return _refused(e);
    }
    return platform_audited(
        me.root_id,
        me.email,
        "platform.cinema_suspended",
        "cinema",
        str(slug),
        lambda -> any { return _suspend(slug, reason, me.email); },  # jac:ignore[W1037]
        detail=str(reason or "")[:DISPUTE_MAX]
    );
}

def:protect platform_reinstate_cinema(slug: str) -> dict[str, any] {  # jac:ignore[W1037]
    try {
        me = require_platform("platform.suspend");
    } except Refused as e {
        return _refused(e);
    }
    return platform_audited(
        me.root_id,
        me.email,
        "platform.cinema_reinstated",
        "cinema",
        str(slug),
        lambda -> any { return _reinstate(slug, me.email); }  # jac:ignore[W1037]
    );
}

@schedule(trigger=ScheduleTrigger.STATIC, interval=BILLING_SECONDS)
def issue_statements {
    ran("issue_statements", BILLING_SECONDS);
    # Runs as Jac's system identity on every server copy; each month is claimed, and
    # each reminder too.
    cinemas = all_cinemas();
    made = issue_due(cinemas, now());
    if made {
        print(f"billing: issued {made}");
    }
    remind_due(cinemas);
}
