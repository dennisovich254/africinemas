"""Reconciliation's endpoints and job (P15.6, ADR-0085): core/payments/reconcile.jac.

- reconciliation(tenant): the cinema's exceptions and recent cash-ups, for staff who
  read its financial reports (financial_reports.read).
- resolve_exception(tenant, exception_id, note) and upload_mpesa_statement(tenant,
  csv_text): the same staff; in the cinema's audit log.
- count_cash(tenant, counted_cents): a box office cash-up (bookings.create, on shift),
  its result shown only once counted.
- platform_reconciliation(): every cinema's open exceptions; platform_takings():
  AfriCinemas' takings (core/billing/takings.jac); both for platform staff.
- reconcile_payments: the daily check, every RECON_SECONDS on every server copy.
"""

import from core.clock { now }
import from core.authz.context { resolve_context, on_shift }
import from core.authz.policy { Resource, require, Forbidden, ROLE_PERMISSIONS }
import from core.catalog.answers { Refused, answer }
import from core.audit.log { audited }
import from core.tenancy.principal { node_id, act_as, restore }
import from core.tenancy.membership { records_of }
import from core.catalog.storefront_api { cinema_timezone }
import from core.platform.staff_api { require_platform }
import from core.platform.cinemas_api { all_cinemas }
import from core.billing.takings { platform_takings as takings_of }
import from core.payments.reconcile {
    exceptions_of,
    exception_view,
    resolve,
    match_statement,
    cash_up,
    cash_ups_of,
    cash_up_view,
    check_all,
    RECON_SECONDS
}

glob READ: str = "financial_reports.read",
     SELL: str = "bookings.create",
     STATEMENT_MAX: int = 3 * 1024 * 1024,
     CASH_UPS_SHOWN: int = 30;

def _scope(tenant: str) -> any {  # jac:ignore[W1037]
    scope = resolve_context(tenant);
    require(scope.ctx, READ, Resource(tenant_id=scope.ctx.tenant_id));
    return scope;
}

def _me_at(cinema: any) -> str {  # jac:ignore[W1037]
    # The caller's sign-in email at the cinema, as its staff records keep it.
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = [
            m.email
            for m in records_of(cinema)
            if m.staff_root_id == me
        ];
    } finally {
        restore(me);
    }
    return found[0] if found and found[0] else me;
}

def _reconciliation(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    cinema = _scope(tenant).tenant;
    found = [exception_view(e) for e in exceptions_of(cinema)];
    return {
        "ok": True,
        "open": len(
            [
                e
                for e in found
                if e["status"] == "open"
            ]
        ),
        "exceptions": found,
        "cash_ups": [cash_up_view(c) for c in cash_ups_of(cinema)[:CASH_UPS_SHOWN]]
    };
}

def _resolve(tenant: str, exception_id: str, note: str) -> dict[str, any] {  # jac:ignore[W1037]
    cinema = _scope(tenant).tenant;
    done = resolve(cinema, str(exception_id), note, _me_at(cinema));
    return {"ok": True, "exception": exception_view(done)};
}

def _upload(tenant: str, csv_text: str) -> dict[str, any] {  # jac:ignore[W1037]
    cinema = _scope(tenant).tenant;
    if not isinstance(csv_text, str) or not csv_text.strip() {
        raise Refused("empty_statement", "Choose the statement's CSV file.");
    }
    if len(csv_text) > STATEMENT_MAX {
        raise Refused(
            "too_long", "The statement is too big: upload a month at a time."
        );
    }
    return {"ok": True, ** match_statement(cinema, csv_text, cinema_timezone(cinema))};
}

def _count(tenant: str, counted_cents: int) -> dict[str, any] {  # jac:ignore[W1037]
    # On shift, and selling at any of the cinema's venues (box office roles are per venue).
    scope = on_shift(tenant);
    if not any([SELL in ROLE_PERMISSIONS[a.role] for a in scope.ctx.assignments]) {
        raise Forbidden(SELL);
    }
    cinema = scope.tenant;
    done = cash_up(cinema, node_id(root), _me_at(cinema), counted_cents);
    return {"ok": True, "cash_up": cash_up_view(done)};
}

def _platform_reconciliation -> dict[str, any] {  # jac:ignore[W1037]
    require_platform("platform.read");
    rows: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for cinema in all_cinemas() {
        for e in exceptions_of(cinema) {
            if e.status == "open" {
                rows.append(
                    {
                        ** exception_view(e),
                        "cinema_name": cinema.name,
                        "slug": cinema.slug
                    }
                );
            }
        }
    }
    return {"ok": True, "exceptions": rows};
}

def _platform_takings -> dict[str, any] {  # jac:ignore[W1037]
    require_platform("platform.read");
    return {"ok": True, ** takings_of(all_cinemas())};
}

def:protect reconciliation(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _reconciliation(tenant); });  # jac:ignore[W1037]
}

def:protect resolve_exception(
    tenant: str, exception_id: str, note: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "reconcile.resolved",
        "reconcile_exception",
        str(exception_id),
        lambda -> any { return _resolve(tenant, exception_id, note); }  # jac:ignore[W1037]
    );
}

def:protect upload_mpesa_statement(tenant: str, csv_text: str) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "reconcile.statement_uploaded",
        "mpesa_statement",
        "",
        lambda -> any { return _upload(tenant, csv_text); }  # jac:ignore[W1037]
    );
}

def:protect count_cash(tenant: str, counted_cents: int) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "cash.counted",
        "cash_up",
        "",
        lambda -> any { return _count(tenant, counted_cents); }  # jac:ignore[W1037]
    );
}

def:protect platform_reconciliation -> dict[str, any] {  # jac:ignore[W1037]
    return answer(_platform_reconciliation);
}

def:protect platform_takings -> dict[str, any] {  # jac:ignore[W1037]
    return answer(_platform_takings);
}

@schedule(trigger=ScheduleTrigger.STATIC, interval=RECON_SECONDS)
def reconcile_payments {
    # Runs as Jac's system identity on every server copy; each payment is checked once.
    made = check_all(all_cinemas(), now());
    if made {
        print(f"reconcile: {made} new exceptions");
    }
}
