"""Recording staff actions in the cinema's audit log (P7.2, architecture §66, §67;
ADR-0027).

Every staff endpoint that changes something answers through `audited`, which records
exactly one event: who did it, what, to which resource, and the result ("ok" or the
refusal's code). A refused attempt is recorded too, but only when the caller is active
staff of that cinema: someone outside it can't write to its log.

Events live outside the graph, in Jac's shared store (the `jac_docs` table, one document
per event), which runs on its own connection and commits at once:

- No shared node: concurrent staff actions never touch the same row, so they can't make
  each other's requests fail (a graph "trail" node every request wrote did).
- No graph write after the endpoint's work: some work commits part-way (a sale, a
  scan), and a graph write after that could make Jac re-run the whole request (JI-042).
- An event is written "pending" before the work and finished once, after it. Work that
  fails part-way leaves it "pending": the attempt is on record either way.
- Nobody can change or delete an event: only this module writes these documents, only
  `audit_log` reads them, and staff never reach the store.

Never recorded (§66): passwords, tokens, secrets, credentials, ticket codes or customer
contact details. An event holds ids, an action and a short `detail` its endpoint chose.

The only module besides core/claims.jac allowed to use the shared store.
"""

import json;
import from uuid { uuid4 }
import from datetime { datetime, timezone }
import from jaclang.server.shared_store { open_docs_store }
import from core.authz.context { NotFound, resolve_context }
import from core.catalog.answers { answer }
import from core.tenancy.models { StaffGroup, Membership, MemberOf }
import from core.tenancy.principal { node_id }

glob DETAIL_MAX: int = 200,
     PENDING: str = "pending",
     COLLECTION_PREFIX: str = "africinemas:audit:";

class AuditStoreUnavailable(RuntimeError) {}

def _store -> any {  # jac:ignore[W1037]
    store = open_docs_store();
    if store is None {
        raise AuditStoreUnavailable("the shared store is not reachable");
    }
    return store;
}

def collection_of(tenant_id: str) -> str {
    return f"{COLLECTION_PREFIX}{tenant_id}";
}

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
    has collection: str,
        event_id: str;
}

def _open(
    tenant: str,
    action: str,
    resource_type: str,
    resource_id: str,
    result: str,
    detail: str
) -> Opened | None {
    # Writes one event at the cinema `tenant` (its slug) by the caller; None, writing
    # nothing, if the caller isn't active staff there.
    try {
        scope = resolve_context(tenant);
    } except NotFound {
        return None;
    }
    # The real time, not core.clock's (which tests freeze and move), fixed-width so
    # that event ids sort in time order.
    at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ");
    event_id = f"{at}|{uuid4().hex}";
    collection = collection_of(scope.ctx.tenant_id);
    doc = {
        "at": at,
        "actor_id": scope.ctx.member_root_id,
        "actor": _known_as(scope.ctx.tenant_id),
        "action": action,
        "resource_type": resource_type,
        "resource_id": resource_id,
        "result": result,
        "detail": detail[:DETAIL_MAX],
        "correlation_id": uuid4().hex
    };
    _store().rows(
        """
        INSERT INTO jac_docs (collection, id, doc)
        VALUES (:c, :i, CAST(:d AS jsonb))
        ON CONFLICT (collection, id) DO NOTHING
        """,
        {"c": collection, "i": event_id, "d": json.dumps(doc)}
    );
    return Opened(collection=collection, event_id=event_id);
}

def _close(opened: Opened, result: str, resource_id: str) {
    # The event's result, once its endpoint's work is done. Only a pending event is
    # finished, and only once.
    _store().rows(
        """
        UPDATE jac_docs SET doc = doc || CAST(:p AS jsonb)
        WHERE collection = :c AND id = :i AND doc->>'result' = :pending
        """,
        {
            "c": opened.collection,
            "i": opened.event_id,
            "p": json.dumps({"result": result, "resource_id": resource_id}),
            "pending": PENDING
        }
    );
}

def record(
    tenant: str,
    action: str,
    resource_type: str,
    resource_id: str,
    result: str,
    detail: str = ""
) {
    # One finished event at the cinema `tenant` (its slug) by the caller, for work
    # already done (creating a cinema, joining one); nothing if the caller isn't
    # active staff there.
    _open(tenant, action, resource_type, resource_id, result, detail);
}

def events(
    tenant_id: str, before: str, limit: int, action: str
) -> list[dict[str, str]] {
    # Up to `limit` of the cinema's events older than the event `before` ("" for the
    # newest), newest first, of one `action` when given.
    found = _store().rows(
        """
        SELECT id, doc FROM jac_docs
        WHERE collection = :c
          AND (:b = '' OR id < :b)
          AND (:a = '' OR doc->>'action' = :a)
        ORDER BY id DESC
        LIMIT :n
        """,
        {"c": collection_of(tenant_id), "b": before, "a": action, "n": limit}
    );
    shown: list[dict[str, str]] = [];
    for (event_id, doc) in found {
        data: dict[str, any] = json.loads(doc) if isinstance(doc, str) else dict(doc);  # jac:ignore[W1037]
        view = {k: str(v) for (k, v) in data.items()};
        view["event_id"] = str(event_id);
        shown.append(view);
    }
    return shown;
}

def has_event(tenant_id: str, event_id: str) -> bool {
    found = _store().rows(
        "SELECT 1 FROM jac_docs WHERE collection = :c AND id = :i",
        {"c": collection_of(tenant_id), "i": event_id}
    );
    return len(found) > 0;
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
    # Answers with `work` (as `answer`) and records the action: "pending" before the
    # work, its result after. `made` is where a response names what it created
    # ("venue.venue_id"), when resource_id can't.
    opened = _open(tenant, action, resource_type, resource_id, PENDING, detail);
    response = answer(work);
    if opened is not None {
        _close(opened, outcome(response), picked(response, made) or resource_id);
    }
    return response;
}
