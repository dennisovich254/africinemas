"""Reading the cinema's audit log (P7.2, architecture §66, §67; ADR-0027).

audit_log(tenant, before, limit, action) answers the cinema's audit events, newest
first, `limit` at a time (1 to MAX_LIMIT): `before` is the last event id of the page
before ("" for the first page) and `next` the id to pass for the next page ("" at the
end). `action` keeps one action only. It needs a login, an open shift (ADR-0006) and
audit.read: owners and auditors. Nothing deletes or changes an event.
"""

import from core.authz.context { NotFound, scoped }
import from core.catalog.answers { Refused, answer }
import from core.tenancy.principal { node_id, act_as, restore }
import from core.audit.models { AuditEvent }
import from core.audit.log { trail_of }

glob READ: str = "audit.read",
     MAX_LIMIT: int = 100;

def _view(e: AuditEvent) -> dict[str, str] {
    return {
        "event_id": node_id(e),
        "at": e.at,
        "actor_id": e.actor_id,
        "actor": e.actor,
        "action": e.action,
        "resource_type": e.resource_type,
        "resource_id": e.resource_id,
        "result": e.result,
        "detail": e.detail,
        "correlation_id": e.correlation_id
    };
}

def _audit_log(tenant: str, before: str, limit: int, action: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, READ);
    if limit < 1 or limit > MAX_LIMIT {
        raise Refused("bad_limit", f"Ask for 1 to {MAX_LIMIT} events at a time.");
    }
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        trail = trail_of(scope.tenant);
        found = [
            _view(e)
            for e in ([trail-->[?:AuditEvent]] if trail is not None else [])
            if not action or e.action == action
        ];
    } finally {
        restore(me);
    }
    def newest(v: dict[str, str]) -> tuple[str, str] {
        return (v["at"], v["event_id"]);
    }
    ordered = sorted(found, key=newest, reverse=True);
    if before {
        ids = [v["event_id"] for v in ordered];
        if before not in ids {
            raise NotFound();
        }
        ordered = ordered[ids.index(before) + 1:];
    }
    page = ordered[:limit];
    return {
        "ok": True,
        "events": page,
        "next": page[-1]["event_id"] if len(ordered) > limit else ""
    };
}

def:priv audit_log(
    tenant: str, before: str = "", limit: int = 50, action: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _audit_log(tenant, before, limit, action); });  # jac:ignore[W1037]
}
