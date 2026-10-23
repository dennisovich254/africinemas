"""Technical support for cinemas (P13.5a): a cinema asks AfriCinemas for help; we answer.

A request is the cinema's own record (a SupportRequest node on its Tenant, owned by its
principal, like a staff invitation): a category, a status and a thread of messages. Its
staff with support.request (owners, tenant admins, general and finance managers) ask,
read their cinema's requests and reply; AfriCinemas' support staff (platform.support)
read every cinema's in the console's inbox, reply, and close or reopen them.

The status says whose turn it is: "open" (ours: a new request, or the cinema wrote
last), "waiting" (the cinema's: we replied), "closed" (either side closed it; a reply
reopens it). The cinema's actions go to its audit log, ours to the platform's, about
the cinema, so they show in its history (ADR-0059).

What a cinema writes is all we see of its data: support staff have no way into its
bookings or customers. Never put passwords or card numbers in a request; the form says
so.
"""

import from core.clock { now }
import from core.catalog.answers { Refused, answer }
import from core.authz.context { scoped }
import from core.tenancy.models { Tenant }
import from core.tenancy.membership { records_of }
import from core.tenancy.open_cinema { tenant_by_id }
import from core.tenancy.principal {
    node_id,
    act_as,
    restore,
    flush_now,
    system_root_id
}
import from core.audit.log { audited, platform_audited }
import from core.platform.staff_api { require_platform, PlatformCaller }
import from core.platform.cinemas_api { all_cinemas }

glob ASK: str = "support.request",
     TEXT_MAX: int = 4000,
     OPEN: str = "open",
     WAITING: str = "waiting",
     CLOSED: str = "closed",
     STATUSES: list[str] = ["open", "waiting", "closed"],
     STATUS_LABELS: dict[str, str] = {
         "open": "Open",
         "waiting": "Waiting for the cinema",
         "closed": "Closed"
     },
     CATEGORIES: dict[str, str] = {
         "payments": "Payments and M-Pesa",
         "emails": "Emails",
         "storefront": "Storefront",
         "verification": "Verification",
         "other": "Something else"
     },
     CINEMA: str = "cinema",
     AFRICINEMAS: str = "africinemas";

node SupportRequest {
    # One help request of the cinema it hangs off, owned by its principal. `messages`:
    # {"at", "side" ("cinema" or "africinemas"), "by" (their email), "text"}.
    has tenant_id: str,
        category: str,
        status: str = "open",
        created_at: str = "",
        updated_at: str = "",
        messages: list[dict[str, str]] = [];
}

def _text(text: any) -> str {  # jac:ignore[W1037]
    # The message, trimmed; refused when it's empty or too long.
    clean = text.strip() if isinstance(text, str) else "";
    if not clean {
        raise Refused("empty_message", "Write what's happening.");
    }
    if len(clean) > TEXT_MAX {
        raise Refused(
            "message_too_long", f"Keep it to {TEXT_MAX} characters or fewer."
        );
    }
    return clean;
}

def _view(request: SupportRequest, cinema: Tenant | None) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "request_id": node_id(request),
        "category": request.category,
        "category_label": CATEGORIES.get(request.category, request.category),
        "status": request.status,
        "status_label": STATUS_LABELS.get(request.status, request.status),
        "created_at": request.created_at,
        "updated_at": request.updated_at,
        "messages": [dict(m) for m in request.messages],
        "cinema": cinema.name if cinema is not None else "",
        "cinema_slug": cinema.slug if cinema is not None else ""
    };
}

def _requests_of(cinema: Tenant) -> list[SupportRequest] {
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = [r for r in [cinema-->[?:SupportRequest]]];
    } finally {
        restore(me);
    }
    return found;
}

def _newest_first(rows: list[dict[str, any]]) -> list[dict[str, any]] {  # jac:ignore[W1037]
    return sorted(
        rows,
        key=lambda (r: dict[str, any]) -> str { return str(r["updated_at"]); },  # jac:ignore[W1037]
        reverse=True
    );
}

def _add(
    cinema: Tenant,
    request: SupportRequest,
    side: str,
    author: str,
    text: str,
    status: str
) {
    # Appends a message and sets the status, as the cinema's principal.
    at = now().isoformat();
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        request.messages = request.messages
            + [{"at": at, "side": side, "by": author, "text": text}];
        request.status = status;
        request.updated_at = at;
        flush_now();
    } finally {
        restore(me);
    }
}

def _sign_in_of(cinema: Tenant) -> str {
    # The caller's sign-in email at this cinema, as its staff records keep it.
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
    return found[0] if found else "";
}

# --- The cinema's side -----------------------------------------------------------------

def _scope(tenant: str) -> any {  # jac:ignore[W1037]
    # The cinema, for a caller who may ask for help there (`answer` turns its
    # refusals into the shared responses).
    return scoped(tenant, ASK);
}

def _ask(tenant: str, category: str, text: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = _scope(tenant);
    if category not in CATEGORIES {
        raise Refused("invalid_category", "Choose what it's about.");
    }
    clean = _text(text);
    cinema: Tenant = scope.tenant;
    at = now().isoformat();
    author = _sign_in_of(cinema);
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        request = SupportRequest(
            tenant_id=node_id(cinema),
            category=category,
            status=OPEN,
            created_at=at,
            updated_at=at,
            messages=[{"at": at, "side": CINEMA, "by": author, "text": clean}]
        );
        cinema ++> request;
        flush_now();
    } finally {
        restore(me);
    }
    return {"ok": True, "request": _view(request, cinema)};
}

def _mine(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = _scope(tenant);
    cinema: Tenant = scope.tenant;
    return {
        "ok": True,
        "requests": _newest_first([_view(r, cinema) for r in _requests_of(cinema)]),
        "categories": [{"key": k, "label": v} for (k, v) in CATEGORIES.items()]
    };
}

def _cinema_reply(tenant: str, request_id: str, text: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = _scope(tenant);
    cinema: Tenant = scope.tenant;
    clean = _text(text);
    found = [
        r
        for r in _requests_of(cinema)
        if node_id(r) == request_id
    ];
    if not found {
        raise Refused("not_found", "No such request.");
    }
    _add(cinema, found[0], CINEMA, _sign_in_of(cinema), clean, OPEN);
    return {"ok": True, "request": _view(found[0], cinema)};
}

def:protect ask_for_help(tenant: str, category: str, text: str) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "support.requested",
        "support_request",
        "",
        lambda -> any { return _ask(tenant, category, text); },  # jac:ignore[W1037]
        made="request.request_id",
        detail=str(category)
    );
}

def:protect support_requests(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _mine(tenant); });  # jac:ignore[W1037]
}

def:protect reply_to_support(
    tenant: str, request_id: str, text: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "support.replied",
        "support_request",
        str(request_id),
        lambda -> any { return _cinema_reply(tenant, request_id, text); }  # jac:ignore[W1037]
    );
}

# --- AfriCinemas' side -----------------------------------------------------------------

def _find(request_id: str) -> tuple[Tenant, SupportRequest] {
    # The request with this id and its cinema, whichever cinema it is.
    me = node_id(root);
    act_as(system_root_id());
    try {
        # JI-053: one short line, so the formatter keeps the ignore on it.
        wanted = request_id if isinstance(request_id, str) else "";
        found: any = jobj(wanted) if wanted else None;  # jac:ignore[W1037]
    } except Exception {
        found = None;
    } finally {
        restore(me);
    }
    if not isinstance(found, SupportRequest) {
        raise Refused("not_found", "No such request.");
    }
    request: SupportRequest = found;
    cinema = tenant_by_id(request.tenant_id);
    if cinema is None {
        raise Refused("not_found", "No such request.");
    }
    return (cinema, request);
}

def _inbox(status: str) -> dict[str, any] {  # jac:ignore[W1037]
    require_platform("platform.support");
    if status and status not in STATUSES {
        raise Refused("invalid_status", "Choose open, waiting or closed.");
    }
    rows: list[dict[str, any]] = [];  # jac:ignore[W1037]
    counts = {s: 0 for s in STATUSES};
    for cinema in all_cinemas() {
        for r in _requests_of(cinema) {
            counts[r.status] = counts.get(r.status, 0) + 1;
            if not status or r.status == status {
                rows.append(_view(r, cinema));
            }
        }
    }
    return {
        "ok": True,
        "requests": _newest_first(rows),
        "counts": [
            {"key": s, "label": STATUS_LABELS[s], "count": counts[s]} for s in STATUSES
        ]
    };
}

def _platform_request(request_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    require_platform("platform.support");
    (cinema, request) = _find(request_id);
    return {"ok": True, "request": _view(request, cinema)};
}

def _answer(request_id: str, text: str, me: PlatformCaller) -> dict[str, any] {  # jac:ignore[W1037]
    (cinema, request) = _find(request_id);
    _add(cinema, request, AFRICINEMAS, me.email, _text(text), WAITING);
    return {"ok": True, "request": _view(request, cinema)};
}

def _set_status(request_id: str, status: str) -> dict[str, any] {  # jac:ignore[W1037]
    if status not in [OPEN, CLOSED] {
        raise Refused("invalid_status", "Close or reopen the request.");
    }
    (cinema, request) = _find(request_id);
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        request.status = status;
        request.updated_at = now().isoformat();
        flush_now();
    } finally {
        restore(me);
    }
    return {"ok": True, "request": _view(request, cinema)};
}

def _cinema_id_of(request_id: str) -> str {
    # The cinema a request belongs to, for the platform's log ("" if there's none).
    try {
        (cinema, _) = _find(request_id);
        return node_id(cinema);
    } except Refused {
        return "";
    }
}

def:protect platform_support_requests(status: str = "") -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _inbox(status); });  # jac:ignore[W1037]
}

def:protect platform_support_request(request_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _platform_request(request_id); });  # jac:ignore[W1037]
}

def:protect platform_support_reply(request_id: str, text: str) -> dict[str, any] {  # jac:ignore[W1037]
    try {
        me = require_platform("platform.support");
    } except Refused as e {
        return answer(lambda -> any { raise e; });  # jac:ignore[W1037]
    }
    return platform_audited(
        me.root_id,
        me.email,
        "platform.support_replied",
        "cinema",
        _cinema_id_of(request_id),
        lambda -> any { return _answer(request_id, text, me); }  # jac:ignore[W1037]
    );
}

def:protect platform_support_status(request_id: str, status: str) -> dict[str, any] {  # jac:ignore[W1037]
    try {
        me = require_platform("platform.support");
    } except Refused as e {
        return answer(lambda -> any { raise e; });  # jac:ignore[W1037]
    }
    return platform_audited(
        me.root_id,
        me.email,
        "platform.support_closed" if status == CLOSED else "platform.support_reopened",
        "cinema",
        _cinema_id_of(request_id),
        lambda -> any { return _set_status(request_id, status); }  # jac:ignore[W1037]
    );
}
