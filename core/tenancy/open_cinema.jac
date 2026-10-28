"""Finding the cinema behind a storefront slug, for public and customer endpoints.

The caller isn't staff, so can't read the Tenant node itself: it's read as the system
root. Only an **active** cinema is public (P14.1, ADR-0064): one still being set up or
waiting for review answers as unknown, with no hint that it exists, so a fake can't
take a customer's money before AfriCinemas has verified it.

Its own team sees it before then through a **preview pass** (preview_pass, from the
back office): a short-lived token for that one cinema, which the storefront page sends
with each request in the PREVIEW_HEADER header. With a valid pass, open_cinema finds the
cinema whatever its state before going live; is_preview says so, and taking money
(placing an order, starting a payment) still needs it active.
"""

import from jaclang.server.exchange { current_request }
import from jaclang.server.identity.app_tokens { token_create, token_peek }
import from core.catalog.answers { Refused }
import from core.tenancy.models { Tenant }
import from core.tenancy.registry { lookup_slug }
import from core.tenancy.principal { node_id, act_as, restore, system_root_id }
import from core.legal.agreement { may_sell }

glob PUBLIC_STATES: list[str] = ["active"],
     # States a preview pass opens: before going live.
     PREVIEW_STATES: list[str] = ["configuring", "ready_for_go_live"],
     PREVIEW_PURPOSE: str = "storefront-preview",
     PREVIEW_HEADER: str = "x-africinemas-preview",
     PREVIEW_TTL_S: int = 8 * 3600,
     # Suspended by AfriCinemas (P15.5): its storefront says so, and takes nothing.
     SUSPENDED: str = "suspended",
     UNAVAILABLE: str = "This cinema isn't available right now.";

def preview_pass(cinema: Tenant) -> str {
    # A pass to preview `cinema`'s storefront before it goes live.
    return token_create(
        PREVIEW_PURPOSE,
        subject=node_id(cinema),
        ttl_seconds=PREVIEW_TTL_S,
        payload={"tenant_id": node_id(cinema)}
    );
}

def _passed(cinema: Tenant) -> bool {
    # Whether this request carries a valid preview pass for `cinema`.
    request = current_request();
    shown = request.header(PREVIEW_HEADER, "") if request is not None else "";
    found = token_peek(PREVIEW_PURPOSE, shown) if shown else None;
    return found is not None and found["payload"].get("tenant_id") == node_id(cinema);
}

def is_preview(cinema: Tenant) -> bool {
    # Seen through a preview pass, not by the public: it isn't live yet.
    return cinema.state not in PUBLIC_STATES;
}

def require_live(cinema: Tenant) {
    # Taking money needs a live cinema: never in a preview, online or at the counter.
    if cinema.state == SUSPENDED {
        raise Refused("suspended", UNAVAILABLE);
    }
    if is_preview(cinema) {
        raise Refused(
            "not_live",
            "This cinema isn't taking bookings yet. It goes live once AfriCinemas has verified it."
        );
    }
    # A new version of the cinema agreement waits for the owner (P15.1).
    if not may_sell(cinema) {
        raise Refused(
            "agreement_needed",
            "This cinema isn't taking bookings right now. Please try again later."
        );
    }
}

def open_cinema(selector: str) -> Tenant | None {
    # The public cinema with this slug, or one its team is previewing; None if unknown,
    # malformed, or not public to this request.
    tenant_id = lookup_slug(selector) if selector else None;
    if tenant_id is None {
        return None;
    }
    me = node_id(root);
    act_as(system_root_id());
    try {
        found: any = jobj(tenant_id);  # jac:ignore[W1037]
    } finally {
        restore(me);
    }
    if not isinstance(found, Tenant) {
        return None;
    }
    cinema = found as Tenant;
    if cinema.state in PUBLIC_STATES {
        return cinema;
    }
    if cinema.state in PREVIEW_STATES and _passed(cinema) {
        return cinema;
    }
    return None;
}

def is_suspended(selector: str) -> bool {
    # Whether the cinema at this slug is suspended (its storefront says it's unavailable).
    tenant_id = lookup_slug(selector) if selector else None;
    found = tenant_by_id(str(tenant_id)) if tenant_id else None;
    return found is not None and found.state == SUSPENDED;
}

def tenant_by_id(tenant_id: str) -> Tenant | None {
    # The cinema with this id whatever its state, for system jobs (payments, mail).
    me = node_id(root);
    act_as(system_root_id());
    try {
        found: any = jobj(tenant_id);  # jac:ignore[W1037]
    } except Exception {
        found = None;
    } finally {
        restore(me);
    }
    return found as Tenant if isinstance(found, Tenant) else None;
}
