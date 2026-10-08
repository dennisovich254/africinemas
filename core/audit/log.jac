"""Recording staff actions in the cinema's audit log (P7.2, architecture §66, §67;
ADR-0027).

Every staff endpoint that changes something answers through `audited`, which records
exactly one AuditEvent: who did it, what, to which resource, and the result ("ok" or the
refusal's code). The event is written before the work and finished after it. A refused attempt is
recorded too, but only when the caller is active staff of that cinema: someone outside
it can't write to its log. Work that fails with an unexpected error rolls back with its
event, unless part of it had committed: then the event stays "pending", the record of an
action that didn't finish.

Never recorded (§66): passwords, tokens, secrets, credentials, ticket codes or customer
contact details. An event holds ids, an action and a short `detail` its endpoint chose.
"""

import from uuid { UUID, uuid4 }
import from jaclang { JacRuntime as Jac }
import from datetime { datetime, timezone }
import from core.authz.context { NotFound, resolve_context }
import from core.catalog.answers { answer }
import from core.tenancy.models { Tenant, StaffGroup, Membership, MemberOf }
import from core.tenancy.principal { node_id, act_as, restore, flush_now }
import from core.tenancy.groups { access_group }
import from core.audit.models { AuditTrail, AuditEvent }

glob DETAIL_MAX: int = 200;

def outcome(response: any) -> str {  # jac:ignore[W1037]
    # "ok" for a response that did what was asked, else its refusal code.
    if isinstance(response, dict) {
        if response.get("ok") is True or response.get("created") is True {
            return "ok";
        }
        error = response.get("error");
        if isinstance(error, dict) and error.get("code") {
            return str(error["code"]);
        }
    }
    return "refused";
}

def picked(response: any, path: str) -> str {  # jac:ignore[W1037]
    # The value at the dotted `path` in a response ("venue.venue_id"); "" if absent.
    if not path {
        return "";
    }
    found: any = response;  # jac:ignore[W1037]
    for key in path.split(".") {
        if not isinstance(found, dict) {
            return "";
        }
        found = found.get(key);
    }
    return "" if found is None else str(found);
}

def trail_of(tenant: Tenant) -> AuditTrail | None {
    # The cinema's audit trail, if it has one. Call as the cinema's principal.
    for t in [tenant-->[?:AuditTrail]] {
        return t;
    }
    return None;
}

def _known_as(tenant_id: str) -> str {
    # How the caller is known at the cinema: their email, else the invitation's label,
    # else their role (an owner has neither until they verify their email).
    me = node_id(root);
    for g in [root->:MemberOf:->[?:StaffGroup]] {
        if g.tenant_id != tenant_id {
            continue;
        }
        for m in [g-->[?:Membership]] {
            if m.staff_root_id == me {
                roles = sorted([key.partition("@")[0] for key in m.roles]);
                return m.email or m.label or (roles[0] if roles else "");
            }
        }
    }
    return "";
}

obj Opened {
    # An event written before its endpoint's work, to finish with the result after.
    has event: AuditEvent,
        principal_root_id: str;
}

def _open(
    tenant: str,
    action: str,
    resource_type: str,
    resource_id: str,
    result: str,
    detail: str
) -> Opened | None {
    # Writes one event at the cinema `tenant` (its slug) by the caller, as the cinema's
    # principal; None, writing nothing, if the caller isn't active staff there.
    try {
        scope = resolve_context(tenant);
    } except NotFound {
        return None;
    }
    cinema = scope.tenant;
    actor = scope.ctx.member_root_id;
    known_as = _known_as(scope.ctx.tenant_id);
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        trail = trail_of(cinema);
        if trail is None {
            trail = AuditTrail(tenant_id=node_id(cinema));
            cinema ++> trail;
        }
        event = AuditEvent(
            tenant_id=node_id(cinema),
            # The real time, not core.clock's (which tests may freeze or move): when
            # it happened, and the order events are read back in.
            at=datetime.now(timezone.utc).isoformat(),
            actor_id=actor,
            actor=known_as,
            action=action,
            resource_type=resource_type,
            resource_id=resource_id,
            result=result,
            detail=detail[:DETAIL_MAX],
            correlation_id=uuid4().hex
        );
        trail ++> event;
        # Staff may read an event, never write or delete it.
        Jac.allow_group(event, UUID(node_id(access_group(cinema))), AccessLevel.READ);  # jac:ignore[E1053]
        # Written now, as the principal: the end-of-request flush runs as the caller,
        # who may only read the event, and would be refused.
        flush_now();
    } finally {
        restore(me);
    }
    return Opened(event=event, principal_root_id=cinema.principal_root_id);
}

def _close(opened: Opened, result: str, resource_id: str) {
    # The event's result, once its endpoint's work is done.
    me = node_id(root);
    act_as(opened.principal_root_id);
    try {
        opened.event.result = result;
        opened.event.resource_id = resource_id;
        flush_now();
    } finally {
        restore(me);
    }
}

def record(
    tenant: str,
    action: str,
    resource_type: str,
    resource_id: str,
    result: str,
    detail: str = ""
) {
    # One finished event at the cinema `tenant` (its slug) by the caller; nothing if
    # the caller isn't active staff there. For work already done in this request that
    # didn't commit part-way (creating a cinema, joining one).
    _open(tenant, action, resource_type, resource_id, result, detail);
}

def audited(
    tenant: str,
    action: str,
    resource_type: str,
    resource_id: str,
    work: any,  # jac:ignore[W1037]
    made: str = "",
    detail: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    # Answers with `work` (as `answer`) and records the action. `made` is where a
    # response names what it created ("venue.venue_id"), when resource_id can't.
    #
    # The event is written before the work, "pending", and given its result after, so
    # work that commits part-way and then fails leaves a pending event. (A write after
    # such a commit once made Jac re-run the whole request, doing a sale twice; the
    # read tier that did it is off, JI-042.)
    opened = _open(tenant, action, resource_type, resource_id, "pending", detail);
    response = answer(work);
    if opened is not None {
        _close(opened, outcome(response), picked(response, made) or resource_id);
    }
    return response;
}
