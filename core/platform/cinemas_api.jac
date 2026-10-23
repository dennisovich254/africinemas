"""The cinemas directory (P13.2): every cinema on the platform, for AfriCinemas staff.

Endpoints listed in tests/isolation/registry.jac with the "platform" scope; any platform
role may read them (platform.read), and they change nothing.

- platform_cinemas(search, state, page, per_page): every cinema, newest first, in pages
  (PAGE_SIZE, at most PAGE_MAX);
  `search` matches the name, the slug or an owner's email, and `state` one state.
- platform_cinema(slug): one cinema's page: its details, owners, staff count, venues
  and screens, tickets sold and takings so far, and its state history (its sign-up,
  then every platform action on it, from the platform's audit log).

No customer's personal data: a cinema's customers appear only as counts. A cinema's
records are read as its principal, the way its own reports read them.
"""

import from core.claims { claims_in }
import from core.catalog.answers { Refused, answer }
import from core.catalog.models { Venue, Auditorium }
import from core.catalog.pricing { CURRENCY }
import from core.tenancy.models { Tenant }
import from core.tenancy.registry { SLUG_NAMESPACE }
import from core.tenancy.open_cinema { tenant_by_id }
import from core.tenancy.membership { records_of }
import from core.tenancy.principal { node_id, act_as, restore }
import from core.reporting.report_api { cinema_records }
import from core.audit.log { events as audit_events }
import from core.platform.staff_api { require_platform }

glob PAGE_SIZE: int = 20,
     PAGE_MAX: int = 50,
     SEARCH_MAX: int = 100,
     HISTORY_MAX: int = 50,
     OWNER: str = "owner",
     STATE_LABELS: dict[str, str] = {
         "configuring": "Setting up",
         "ready_for_go_live": "Ready to go live",
         "active": "Active",
         "suspended": "Suspended",
         "closing": "Closing",
         "deleted": "Deleted"
     };

obj Staffing {
    has owners: list[str] = [],
        staff: int = 0;
}

def _cinemas -> list[Tenant] {
    # Every cinema that finished signing up (a slug held for one still signing up
    # names no cinema yet).
    found: list[Tenant] = [];
    for (_, tenant_id, _) in claims_in(SLUG_NAMESPACE) {
        cinema = tenant_by_id(str(tenant_id));
        if cinema is not None and cinema.state in STATE_LABELS {
            found.append(cinema);
        }
    }
    return found;
}

def _staffing(cinema: Tenant) -> Staffing {
    # Its owners' emails (as they signed in) and how many staff it has.
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        records = [
            m
            for m in records_of(cinema)
            if m.status == "active"
        ];
    } finally {
        restore(me);
    }
    return Staffing(
        owners=sorted(
            [
                m.email
                for m in records
                if OWNER in m.roles and m.email
            ]
        ),
        staff=len(records)
    );
}

def _row(cinema: Tenant, staffing: Staffing) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "name": cinema.name,
        "slug": cinema.slug,
        "state": cinema.state,
        "state_label": STATE_LABELS[cinema.state],
        "signed_up_at": cinema.created_at,
        "owners": staffing.owners
    };
}

def _matches(cinema: Tenant, staffing: Staffing, search: str) -> bool {
    if not search {
        return True;
    }
    return search in cinema.name.lower()
        or search in cinema.slug
        or any([search in e for e in staffing.owners]);
}

def _page_number(value: any, otherwise: int = 1) -> int {  # jac:ignore[W1037]
    # The page numbers are text: an endpoint's number with a default can arrive as
    # text anyway (JI-025), so they're never numbers there.
    try {
        return int(str(value));
    } except ValueError {
        return otherwise;
    }
}

def _directory(search: str, state: str, page: any, per_page: any) -> dict[str, any] {  # jac:ignore[W1037]
    require_platform("platform.read");
    wanted = search.strip().lower()[:SEARCH_MAX] if isinstance(search, str) else "";
    if state and state not in STATE_LABELS {
        raise Refused("invalid_state", "Choose one of the cinema states.");
    }
    rows: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for cinema in _cinemas() {
        if state and cinema.state != state {
            continue;
        }
        staffing = _staffing(cinema);
        if _matches(cinema, staffing, wanted) {
            rows.append(_row(cinema, staffing));
        }
    }
    rows = sorted(
        rows,
        key=lambda (r: dict[str, any]) -> str { return str(r["signed_up_at"]); },  # jac:ignore[W1037]
        reverse=True
    );
    size = min(max(1, _page_number(per_page, PAGE_SIZE)), PAGE_MAX);
    pages = max(1, (len(rows) + size - 1) // size);
    shown = min(max(1, _page_number(page)), pages);
    start = (shown - 1) * size;
    return {
        "ok": True,
        "cinemas": rows[start:start + size],
        "total": len(rows),
        "page": shown,
        "pages": pages,
        "states": [{"key": k, "label": v} for (k, v) in STATE_LABELS.items()]
    };
}

def _venues(cinema: Tenant) -> list[dict[str, any]] {  # jac:ignore[W1037]
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = [
            {
                "name": v.name,
                "city": v.city,
                "screens": sorted([a.name for a in [v-->[?:Auditorium]]])
            } for v in [cinema-->[?:Venue]]
        ];
    } finally {
        restore(me);
    }
    return sorted(
        found,
        key=lambda (v: dict[str, any]) -> str { return str(v["name"]); }  # jac:ignore[W1037]
    );
}

def _history(cinema: Tenant) -> list[dict[str, str]] {
    # Its sign-up, then the platform's actions on it, newest first.
    platform = [
        {"at": e["at"], "what": e["action"], "by": e["actor"], "why": e["detail"]}
        for e in audit_events("platform", "", HISTORY_MAX, "")
        if e["resource_id"] == node_id(cinema) and e["result"] == "ok"
    ];
    return platform
        + [{"at": cinema.created_at, "what": "signed_up", "by": "", "why": ""}];
}

def _cinema(slug: str) -> dict[str, any] {  # jac:ignore[W1037]
    require_platform("platform.read");
    wanted = slug.strip().lower() if isinstance(slug, str) else "";
    found = [
        c
        for c in _cinemas()
        if c.slug == wanted
    ];
    if not found {
        raise Refused("not_found", "No such cinema.");
    }
    cinema = found[0];
    staffing = _staffing(cinema);
    records = cinema_records(cinema);
    page = _row(cinema, staffing);
    page["staff"] = staffing.staff;
    page["venues"] = _venues(cinema);
    page["showtimes"] = len(records.shows);
    page["tickets_sold"] = len(records.tickets);
    page["takings_net_cents"] = sum([m.amount_cents for m in records.money]);
    page["currency"] = CURRENCY;
    page["history"] = _history(cinema);
    return {"ok": True, "cinema": page};
}

def:protect platform_cinemas(
    search: str = "", state: str = "", page: str = "1", per_page: str = "20"
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(
        lambda -> any { return _directory(search, state, page, per_page); }  # jac:ignore[W1037]
    );
}

def:protect platform_cinema(slug: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _cinema(slug); });  # jac:ignore[W1037]
}
