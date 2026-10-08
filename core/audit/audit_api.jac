"""Reading the cinema's audit log (P7.2, architecture §66, §67; ADR-0027).

audit_log(tenant, before, limit, action) answers the cinema's audit events, newest
first, `limit` at a time (1 to MAX_LIMIT): `before` is the last event id of the page
before ("" for the first page) and `next` the id to pass for the next page ("" at the
end). `action` keeps one action only. Events are read from Jac's shared store
(core/audit/log.jac). It needs a login, an open shift (ADR-0006) and
audit.read: owners and auditors. Nothing deletes or changes an event.
"""

import from core.authz.context { NotFound, scoped }
import from core.catalog.answers { Refused, answer }
import from core.audit.log { events, has_event }
import from core.catalog.storefront_api { cinema_timezone }

glob READ: str = "audit.read",
     MAX_LIMIT: int = 100;

def _audit_log(tenant: str, before: str, limit: int, action: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, READ);
    if limit < 1 or limit > MAX_LIMIT {
        raise Refused("bad_limit", f"Ask for 1 to {MAX_LIMIT} events at a time.");
    }
    if before and not has_event(scope.ctx.tenant_id, before) {
        raise NotFound();
    }
    # One more than asked, to know whether there's a next page.
    found = events(scope.ctx.tenant_id, before, limit + 1, action);
    page = found[:limit];
    return {
        "ok": True,
        # Times are UTC; the page shows them in the cinema's zone.
        "timezone": cinema_timezone(scope.tenant),
        "events": page,
        "next": page[-1]["event_id"] if len(found) > limit else ""
    };
}

def:priv audit_log(
    tenant: str, limit: int, before: str = "", action: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _audit_log(tenant, before, limit, action); });  # jac:ignore[W1037]
}
