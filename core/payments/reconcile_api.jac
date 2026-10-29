"""Reconciliation's endpoints and job (P15.6, ADR-0085): core/payments/reconcile.jac.

- reconciliation(tenant): the cinema's exceptions, recent cash-ups and time zone, for
  staff who read its financial reports (financial_reports.read).
- reconciliation_open(tenant): how many are open, for the sidebar's badge; the same
  staff (anyone else is told 0, so the sidebar needn't know who may read them).
- resolve_exception(tenant, exception_id, note): the same staff; in the cinema's audit
  log.
- count_cash(tenant, counted_cents): a box office cash-up (bookings.create, on shift),
  its result shown only once counted. It ends the shift (P15.6b), except a count of
  cash left from an earlier shift ("count_first"), which lets the new one go on.
- recount_cash(tenant, counted_cents): corrects the caller's last count, once, within
  10 minutes; no shift needed, since counting ended it.
- cash_status(tenant): whether the caller has cash to count (not how much: the count is
  blind), whether it's from an earlier shift, and the most one count may be.
- platform_reconciliation(): every cinema's open exceptions; platform_takings():
  AfriCinemas' takings (core/billing/takings.jac); both for platform staff.
- reconcile_payments: the daily check, every RECON_SECONDS on every server copy.
- check_cash_counted: every CASH_CHECK_SECONDS, cash left uncounted at a shift's end.
"""

import os;
import from core.clock { now }
import from core.authz.context { resolve_context, on_shift }
import from core.authz.policy { Resource, require, Forbidden, ROLE_PERMISSIONS }
import from core.catalog.answers { Refused, answer }
import from core.audit.log { audited }
import from core.tenancy.principal { node_id, act_as, restore }
import from core.tenancy.membership { records_of }
import from core.tenancy.shifts { close_shift, shift_is_open, shift_started_at }
import from core.catalog.storefront_api { cinema_timezone }
import from core.platform.staff_api { require_platform }
import from core.platform.cinemas_api { all_cinemas }
import from core.billing.takings { platform_takings as takings_of }
import from core.payments.reconcile {
    exceptions_of,
    exception_view,
    resolve,
    cash_up,
    recount,
    uncounted,
    count_first,
    check_uncounted,
    cash_ups_of,
    cash_up_view,
    check_all,
    RECON_SECONDS
}

glob CASH_CHECK_SECONDS: int = int(
         os.environ.get("AFRICINEMAS_CASH_CHECK_SECONDS", "900")
     ),
     READ: str = "financial_reports.read",
     SELL: str = "bookings.create",
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
        "timezone": cinema_timezone(cinema),
        "cash_ups": [cash_up_view(c) for c in cash_ups_of(cinema)[:CASH_UPS_SHOWN]]
    };
}

def _open_count(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = resolve_context(tenant);
    try {
        require(scope.ctx, READ, Resource(tenant_id=scope.ctx.tenant_id));
    } except Forbidden {
        return {"ok": True, "open": 0};
    }
    found = [
        e
        for e in exceptions_of(scope.tenant)
        if e.status == "open"
    ];
    return {"ok": True, "open": len(found)};
}

def _resolve(tenant: str, exception_id: str, note: str) -> dict[str, any] {  # jac:ignore[W1037]
    cinema = _scope(tenant).tenant;
    done = resolve(cinema, str(exception_id), note, _me_at(cinema));
    return {"ok": True, "exception": exception_view(done)};
}

def _seller(scope: any) -> any {  # jac:ignore[W1037]
    # Selling at any of the cinema's venues (box office roles are per venue).
    if not any([SELL in ROLE_PERMISSIONS[a.role] for a in scope.ctx.assignments]) {
        raise Forbidden(SELL);
    }
    return scope;
}

def _count(tenant: str, counted_cents: int) -> dict[str, any] {  # jac:ignore[W1037]
    scope = _seller(on_shift(tenant));
    cinema = scope.tenant;
    me = node_id(root);
    earlier = count_first(cinema, me, shift_started_at(scope.ctx.tenant_id, me));
    done = cash_up(cinema, me, _me_at(cinema), counted_cents);
    if not earlier {
        close_shift(scope.ctx.tenant_id, me);
    }
    return {"ok": True, "cash_up": cash_up_view(done), "shift_ended": not earlier};
}

def _recount(tenant: str, counted_cents: int) -> dict[str, any] {  # jac:ignore[W1037]
    scope = _seller(resolve_context(tenant));
    done = recount(scope.tenant, node_id(root), counted_cents);
    return {"ok": True, "cash_up": cash_up_view(done)};
}

def _cash_status(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = _seller(resolve_context(tenant));
    me = node_id(root);
    (_, first, _) = uncounted(scope.tenant, me);
    mine = [
        c
        for c in cash_ups_of(scope.tenant)
        if c.member_id == me
    ];
    return {
        "ok": True,
        "uncounted": bool(first),
        "count_first": count_first(
            scope.tenant, me, shift_started_at(scope.ctx.tenant_id, me)
        ),
        "max_cents": scope.tenant.cash_count_max_cents,
        "last": cash_up_view(mine[0]) if mine else None
    };
}

def _names(cinema: any) -> dict[str, str] {  # jac:ignore[W1037]
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        return {
            m.staff_root_id: m.email or m.staff_root_id for m in records_of(cinema)
        };
    } finally {
        restore(me);
    }
}

def check_all_counted -> int {
    made = 0;
    for cinema in all_cinemas() {
        tid = node_id(cinema);
        made += check_uncounted(
            cinema,
            _names(cinema),
            lambda (member_id: str) -> bool { return shift_is_open(tid, member_id); }
        );
    }
    return made;
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
                        "slug": cinema.slug,
                        "timezone": cinema_timezone(cinema)
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

def:protect reconciliation_open(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _open_count(tenant); });  # jac:ignore[W1037]
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

def:protect count_cash(tenant: str, counted_cents: int) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "cash.counted",
        "cash_up",
        "",
        lambda -> any { return _count(tenant, counted_cents); }  # jac:ignore[W1037]
    );
}

def:protect recount_cash(tenant: str, counted_cents: int) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "cash.recounted",
        "cash_up",
        "",
        lambda -> any { return _recount(tenant, counted_cents); }  # jac:ignore[W1037]
    );
}

def:protect cash_status(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _cash_status(tenant); });  # jac:ignore[W1037]
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

@schedule(trigger=ScheduleTrigger.STATIC, interval=CASH_CHECK_SECONDS)
def check_cash_counted {
    # Cash left uncounted when a shift ended (signed out, or it ran out): for managers.
    made = check_all_counted();
    if made {
        print(f"cash counts: {made} not counted");
    }
}
