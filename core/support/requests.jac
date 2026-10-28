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
import io;
import base64;
import from uuid { uuid4 }
import from core.claims { claim }
import from core.support.names { REPLY_MAIL }
import from core.support.health { health_of }
import from core.tenancy.principal { fresh_node_id }
import from core.catalog.poster {
    decode_screenshot,
    process_screenshot,
    media_store,
    media_key,
    read_media,
    PosterRejected
}

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
     # The same statuses as the cinema sees them, from its side.
     CINEMA_STATUS_LABELS: dict[str, str] = {
         "open": "Waiting for AfriCinemas",
         "waiting": "AfriCinemas replied",
         "closed": "Closed"
     },
     CATEGORIES: dict[str, str] = {
         "payments": "Payments and M-Pesa",
         # Booked from Settings -> Payments (P15.3): a call to help connect M-Pesa.
         "setup_call": "A call to set up M-Pesa",
         # Raised on an invoice in Billing (P15.5): what's wrong with it.
         "invoice_dispute": "An invoice I disagree with",
         "emails": "Emails",
         "storefront": "Storefront",
         "verification": "Verification",
         "other": "Something else"
     },
     OWNER: str = "owner",
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
        messages: list[dict[str, str]] = [],
        # When each side last read it (P13.5a): the cinema's staff, and AfriCinemas'
        # support team as one (one inbox), so unread counts clear once read.
        cinema_seen_at: str = "",
        africinemas_seen_at: str = "";
}

def _unread(request: SupportRequest, reader: str) -> int {
    # How many of the other side's messages `reader` hasn't seen yet.
    seen = request.cinema_seen_at if reader == CINEMA else request.africinemas_seen_at;
    return len(
        [
            m
            for m in request.messages
            if m["side"] != reader and m["at"] > (seen or "")
        ]
    );
}

def _text(text: any, optional: bool = False) -> str {  # jac:ignore[W1037]
    # The message, trimmed; refused when it's too long, or empty unless `optional`
    # (a message that's a screenshot alone).
    clean = text.strip() if isinstance(text, str) else "";
    if not clean and not optional {
        raise Refused("empty_message", "Write what's happening.");
    }
    if len(clean) > TEXT_MAX {
        raise Refused(
            "message_too_long", f"Keep it to {TEXT_MAX} characters or fewer."
        );
    }
    return clean;
}

def _screenshot(cinema: Tenant, image_type: str, image_base64: str) -> str {
    # A checked screenshot (P13.5b) stored in the cinema's own media, under a name of
    # ours; its key, or "" when there's none.
    if not image_base64 {
        return "";
    }
    try {
        webp = process_screenshot(decode_screenshot(image_base64), image_type);
    } except PosterRejected as e {
        raise Refused(e.code, e.message);
    }
    key = media_key(node_id(cinema), f"support-{uuid4().hex}");
    media_store().upload(io.BytesIO(webp), key);
    return key;
}

def _shown(message: dict[str, str]) -> dict[str, any] {  # jac:ignore[W1037]
    # A message as the pages see it: whether it has a screenshot, never where it's kept.
    shown: dict[str, any] = dict(message);  # jac:ignore[W1037]
    shown.pop("image", None);
    shown["has_image"] = bool(message.get("image", ""));
    return shown;
}

def _view(
    request: SupportRequest, cinema: Tenant | None, reader: str = "africinemas"
) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "request_id": node_id(request),
        "category": request.category,
        "category_label": CATEGORIES.get(request.category, request.category),
        "status": request.status,
        "status_label": (
            CINEMA_STATUS_LABELS if reader == CINEMA else STATUS_LABELS
        ).get(
            request.status, request.status
        ),
        "created_at": request.created_at,
        "updated_at": request.updated_at,
        "messages": [_shown(m) for m in request.messages],
        "cinema": cinema.name if cinema is not None else "",
        "cinema_slug": cinema.slug if cinema is not None else "",
        "unread": _unread(request, reader)
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

def drop_old_screenshots(cinema: Tenant, closed_before: str, stamp: str) -> int {
    # Deletes the screenshots of the cinema's requests closed before `closed_before`
    # (the retention rule, P14.5b): the written conversation stays, and each message
    # notes when its screenshot went. How many were deleted.
    dropped = 0;
    for request in _requests_of(cinema) {
        if request.status != CLOSED or request.updated_at >= closed_before {
            continue;
        }
        kept: list[dict[str, str]] = [];
        changed = False;
        for m in request.messages {
            message: dict[str, str] = dict(m);
            if message.get("image", "") {
                try {
                    media_store().delete(message["image"]);
                } except Exception as e {
                    print(f"support screenshot of {cinema.slug} already gone: {e}");
                }
                message["image"] = "";
                message["image_removed_at"] = stamp;
                changed = True;
                dropped += 1;
            }
            kept.append(message);
        }
        if changed {
            me = node_id(root);
            act_as(cinema.principal_root_id);
            try {
                request.messages = kept;
                flush_now();
            } finally {
                restore(me);
            }
        }
    }
    return dropped;
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
    status: str,
    image: str = ""
) {
    # Appends a message (with a screenshot's key, or "") and sets the status, as the
    # cinema's principal.
    at = now().isoformat();
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        request.messages = request.messages
            + [{"at": at, "side": side, "by": author, "text": text, "image": image}];
        request.status = status;
        request.updated_at = at;
        # Writing a message means you've read the conversation up to it.
        if side == CINEMA {
            request.cinema_seen_at = at;
        } else {
            request.africinemas_seen_at = at;
        }
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

def _ask(
    tenant: str, category: str, text: str, image_type: str, image_base64: str
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = _scope(tenant);
    if category not in CATEGORIES {
        raise Refused("invalid_category", "Choose what it's about.");
    }
    clean = _text(text, bool(image_base64));
    cinema: Tenant = scope.tenant;
    image = _screenshot(cinema, image_type, image_base64);
    return {"ok": True, "request": _filed(cinema, category, clean, image)};
}

def file_request(cinema: Tenant, category: str, text: str) -> dict[str, any] {  # jac:ignore[W1037]
    # A request opened for the caller by another page (an invoice's dispute, P15.5),
    # which has checked who may; its view.
    return _filed(cinema, category, _text(text, False), "");
}

def _filed(cinema: Tenant, category: str, clean: str, image: str) -> dict[str, any] {  # jac:ignore[W1037]
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
            messages=[
                {"at": at, "side": CINEMA, "by": author, "text": clean, "image": image}
            ],
            cinema_seen_at=at
        );
        cinema ++> request;
        flush_now();
    } finally {
        restore(me);
    }
    return _view(request, cinema, CINEMA);
}

def _mine(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = _scope(tenant);
    cinema: Tenant = scope.tenant;
    return {
        "ok": True,
        "requests": _newest_first(
            [_view(r, cinema, CINEMA) for r in _requests_of(cinema)]
        ),
        "categories": [{"key": k, "label": v} for (k, v) in CATEGORIES.items()]
    };
}

def _cinema_reply(
    tenant: str, request_id: str, text: str, image_type: str, image_base64: str
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = _scope(tenant);
    cinema: Tenant = scope.tenant;
    clean = _text(text, bool(image_base64));
    found = [
        r
        for r in _requests_of(cinema)
        if node_id(r) == request_id
    ];
    if not found {
        raise Refused("not_found", "No such request.");
    }
    image = _screenshot(cinema, image_type, image_base64);
    _add(cinema, found[0], CINEMA, _sign_in_of(cinema), clean, OPEN, image);
    return {"ok": True, "request": _view(found[0], cinema, CINEMA)};
}

def:protect ask_for_help(
    tenant: str, category: str, text: str, image_type: str = "", image_base64: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    # `image_base64`: an optional screenshot (JPEG, PNG or WebP, up to 3 MB).
    return audited(
        tenant,
        "support.requested",
        "support_request",
        "",
        lambda -> any { return _ask(
            tenant, category, text, image_type, image_base64
        ); },  # jac:ignore[W1037]
        made="request.request_id",
        detail=str(category)
    );
}

def:protect support_requests(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _mine(tenant); });  # jac:ignore[W1037]
}

def:protect reply_to_support(
    tenant: str,
    request_id: str,
    text: str,
    image_type: str = "",
    image_base64: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "support.replied",
        "support_request",
        str(request_id),
        lambda -> any { return _cinema_reply(  # jac:ignore[W1037]
            tenant, request_id, text, image_type, image_base64
        ); }
    );
}

def _image_of(request: SupportRequest, index: int) -> dict[str, any] {  # jac:ignore[W1037]
    # The screenshot of message `index`, as base64 WebP, like a poster (movie_api).
    messages = request.messages;
    if not isinstance(index, int) or index < 0 or index >= len(messages) {
        raise Refused("not_found", "No such screenshot.");
    }
    data = read_media(messages[index].get("image", ""));
    if data is None {
        raise Refused("not_found", "No such screenshot.");
    }
    return {
        "ok": True,
        "content_type": "image/webp",
        "data_base64": base64.b64encode(data).decode()
    };
}

def _cinema_image(tenant: str, request_id: str, index: int) -> dict[str, any] {  # jac:ignore[W1037]
    scope = _scope(tenant);
    found = [
        r
        for r in _requests_of(scope.tenant)
        if node_id(r) == request_id
    ];
    if not found {
        raise Refused("not_found", "No such screenshot.");
    }
    return _image_of(found[0], index);
}

def:protect support_image(tenant: str, request_id: str, index: int) -> dict[str, any] {  # jac:ignore[W1037]
    # A screenshot in one of the cinema's own requests.
    return answer(lambda -> any { return _cinema_image(tenant, request_id, index); });  # jac:ignore[W1037]
}

def _mark_seen(cinema: Tenant, request: SupportRequest, reader: str) {
    # `reader` has read every message so far, as the cinema's principal.
    at = now().isoformat();
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        if reader == CINEMA {
            request.cinema_seen_at = at;
        } else {
            request.africinemas_seen_at = at;
        }
        flush_now();
    } finally {
        restore(me);
    }
}

def _cinema_seen(tenant: str, request_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = _scope(tenant);
    cinema: Tenant = scope.tenant;
    found = [
        r
        for r in _requests_of(cinema)
        if node_id(r) == request_id
    ];
    if not found {
        raise Refused("not_found", "No such request.");
    }
    if _unread(found[0], CINEMA) {
        _mark_seen(cinema, found[0], CINEMA);
    }
    return {"ok": True, "request": _view(found[0], cinema, CINEMA)};
}

def:protect support_seen(tenant: str, request_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The cinema has read a conversation: its unread count clears.
    return answer(lambda -> any { return _cinema_seen(tenant, request_id); });  # jac:ignore[W1037]
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
    # Requests with cinema messages we haven't read, whatever their status.
    unread = 0;
    for cinema in all_cinemas() {
        for r in _requests_of(cinema) {
            counts[r.status] = counts.get(r.status, 0) + 1;
            if _unread(r, AFRICINEMAS) {
                unread += 1;
            }
            if not status or r.status == status {
                rows.append(_view(r, cinema));
            }
        }
    }
    return {
        "ok": True,
        "unread": unread,
        "requests": _newest_first(rows),
        "counts": [
            {"key": s, "label": STATUS_LABELS[s], "count": counts[s]} for s in STATUSES
        ]
    };
}

def _platform_request(request_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The request, with its cinema's technical health beside it (P13.5c).
    require_platform("platform.support");
    (cinema, request) = _find(request_id);
    return {"ok": True, "request": _view(request, cinema), "health": health_of(cinema)};
}

def owner_emails(cinema: Tenant) -> list[str] {
    # The cinema's owners' sign-in emails (P13.5b), for telling them we've replied.
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = sorted(
            set(
                [
                    m.email
                    for m in records_of(cinema)
                    if OWNER in m.roles and m.status == "active" and m.email
                ]
            )
        );
    } finally {
        restore(me);
    }
    return found;
}

def _answer(
    request_id: str, text: str, image_type: str, image_base64: str, me: PlatformCaller
) -> dict[str, any] {  # jac:ignore[W1037]
    (cinema, request) = _find(request_id);
    clean = _text(text, bool(image_base64));
    image = _screenshot(cinema, image_type, image_base64);
    _add(cinema, request, AFRICINEMAS, me.email, clean, WAITING, image);
    # One email to each owner, sent by the mail job, never inside the request.
    for address in owner_emails(cinema) {
        claim(REPLY_MAIL, fresh_node_id(), f"{node_id(cinema)}|{request_id}|{address}");
    }
    return {"ok": True, "request": _view(request, cinema)};
}

def request_of(request_id: str) -> tuple[Tenant, SupportRequest] | None {
    # The request and its cinema, for the mail job; None when either is gone.
    try {
        return _find(request_id);
    } except Refused {
        return None;
    }
}

def _platform_image(request_id: str, index: int) -> dict[str, any] {  # jac:ignore[W1037]
    require_platform("platform.support");
    (_, request) = _find(request_id);
    return _image_of(request, index);
}

def:protect platform_support_image(request_id: str, index: int) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _platform_image(request_id, index); });  # jac:ignore[W1037]
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

def _platform_seen(request_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    require_platform("platform.support");
    (cinema, request) = _find(request_id);
    if _unread(request, AFRICINEMAS) {
        _mark_seen(cinema, request, AFRICINEMAS);
    }
    return {"ok": True, "request": _view(request, cinema)};
}

def:protect platform_support_seen(request_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    # Our team has read a request: its unread count clears, for everyone on it.
    return answer(lambda -> any { return _platform_seen(request_id); });  # jac:ignore[W1037]
}

def:protect platform_support_requests(status: str = "") -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _inbox(status); });  # jac:ignore[W1037]
}

def:protect platform_support_request(request_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _platform_request(request_id); });  # jac:ignore[W1037]
}

def:protect platform_support_reply(
    request_id: str, text: str, image_type: str = "", image_base64: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
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
        lambda -> any { return _answer(  # jac:ignore[W1037]
            request_id, text, image_type, image_base64, me
        ); }
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
