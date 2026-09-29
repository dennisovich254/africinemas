"""Seat layouts with versioning (P3.2, architecture §21, §22). Tenant-scoped endpoints,
listed in tests/isolation/registry.jac.

- save_layout writes the screen's draft. If the screen has no draft (its first layout,
  or its latest version is published), it creates the next version. A published version
  is never changed.
- publish_layout freezes the draft, once it passes check_layout and has a seat to sell.
- list_layouts and get_layout read versions; a layout id always returns that version,
  so screenings (3.5) and tickets keep the seats they were sold on.
- Reading needs seats.read and changing needs seats.configure, both at the screen's
  venue. Another cinema's screen or layout ids answer not_found.
- One save or publish per screen at a time: each holds the screen's edit lock (an
  atomic claim, ADR-0007) until it commits, and a concurrent one is refused with
  layout_busy. Each version number is a claim too, so no version is created twice.
"""

import from core.clock { now }
import from core.claims { claim, make_permanent, release }
import from core.authz.policy { Resource, require }
import from core.authz.context { NotFound, TenantScope, on_shift }
import from core.tenancy.groups { attach_to_tenant }
import from core.tenancy.principal {
    node_id,
    act_as,
    restore,
    flush_now,
    fresh_node_id,
    assign_id
}
import from core.catalog.layout {
    Seat,
    LayoutProblem,
    parse_seats,
    check_layout,
    sellable_count
}
import from core.catalog.models {
    Auditorium,
    SeatLayout,
    LAYOUT_VERSIONS,
    DRAFT,
    PUBLISHED
}
import from core.catalog.answers { Refused, answer }
import from core.catalog.venues {
    find_auditorium,
    find_layout,
    layouts_of,
    version_key
}

glob READ: str = "seats.read",
     CONFIGURE: str = "seats.configure",
     CLAIM_HOLD_S: int = 300,
     # One writer per screen's layouts at a time (see _lock_screen).
     LAYOUT_EDITS: str = "layout-edit",
     EDIT_HOLD_S: int = 15;

def _screen(scope: TenantScope, auditorium_id: str, action: str) -> Auditorium {
    # The caller's screen, once they may do `action` at its venue.
    screen = find_auditorium(scope.tenant, auditorium_id);
    if screen is None {
        raise NotFound();
    }
    require(
        scope.ctx,
        action,
        Resource(tenant_id=scope.ctx.tenant_id, venue_id=screen.venue_id)
    );
    return screen;
}

def _invalid(problems: list[LayoutProblem]) -> Refused {
    return Refused(
        "invalid_layout",
        "This layout has problems to fix before it can be saved.",
        {
            "problems": [
                {"code": p.code, "message": p.message, "label": p.label}
                for p in problems
            ]
        }
    );
}

def _seat_view(s: Seat) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "label": s.label,
        "row": s.row,
        "col": s.col,
        "seat_type": s.seat_type,
        "zone": s.zone
    };
}

def _summary(l: SeatLayout) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "layout_id": node_id(l),
        "auditorium_id": l.auditorium_id,
        "version": l.version,
        "status": l.status,
        "rows": l.rows,
        "cols": l.cols,
        "seat_count": len(l.seats),
        "sellable_seats": sellable_count(l.seats),
        "published_at": l.published_at
    };
}

def _view(l: SeatLayout) -> dict[str, any] {  # jac:ignore[W1037]
    view = _summary(l);
    view["seats"] = [_seat_view(s) for s in l.seats];
    return view;
}

def _lock_screen(auditorium_id: str) -> str {
    # Takes the screen's edit lock, an atomic claim held until this request commits (or
    # fails, or EDIT_HOLD_S passes if the server dies). Two saves of one draft would
    # otherwise update the same node at once, and the database refuses all but one of
    # them (a serialization failure); a caller who finds the lock taken is told to retry
    # instead. Returns the lock's owner id.
    owner = fresh_node_id();
    if claim(LAYOUT_EDITS, auditorium_id, owner, EDIT_HOLD_S) != owner {
        raise Refused(
            "layout_busy",
            "Someone else is saving this screen's layout. Reload it and try again."
        );
    }
    on_commit(lambda { release(LAYOUT_EDITS, auditorium_id, owner); });
    return owner;
}

def _draft_of(layouts: list[SeatLayout]) -> SeatLayout | None {
    # The screen's draft: its latest version, when that isn't published yet.
    return layouts[-1] if layouts and layouts[-1].status == DRAFT else None;
}

def _save_layout(
    tenant: str,
    auditorium_id: str,
    rows: int,
    cols: int,
    seats: list[any]  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = on_shift(tenant);
    screen = _screen(scope, auditorium_id, CONFIGURE);
    (parsed, problems) = parse_seats(seats);
    problems = problems + check_layout(rows, cols, parsed);
    if problems {
        raise _invalid(problems);
    }
    lock = _lock_screen(auditorium_id);
    try {
        return _write_layout(scope, screen, rows, cols, parsed);
    } except Exception as e {
        release(LAYOUT_EDITS, auditorium_id, lock);
        raise e;
    }
}

def _write_layout(
    scope: TenantScope, screen: Auditorium, rows: int, cols: int, parsed: list[Seat]
) -> dict[str, any] {  # jac:ignore[W1037]
    # save_layout's work, under the screen's edit lock.
    auditorium_id = node_id(screen);
    stamp = now().isoformat();
    layouts = layouts_of(scope.tenant, screen);
    draft = _draft_of(layouts);
    me = node_id(root);
    if draft is not None {
        act_as(scope.tenant.principal_root_id);
        try {
            draft.rows = rows;
            draft.cols = cols;
            draft.seats = parsed;
            draft.updated_at = stamp;
            flush_now();
        } finally {
            restore(me);
        }
        return {"ok": True, "layout": _view(draft)};
    }
    version = layouts[-1].version + 1 if layouts else 1;
    layout_id = fresh_node_id();
    key = version_key(auditorium_id, version);
    if claim(LAYOUT_VERSIONS, key, layout_id, CLAIM_HOLD_S) != layout_id {
        raise Refused(
            "layout_busy",
            "Someone else is saving this screen's layout. Reload it and try again."
        );
    }
    act_as(scope.tenant.principal_root_id);
    try {
        layout = SeatLayout(
            tenant_id=scope.ctx.tenant_id,
            venue_id=screen.venue_id,
            auditorium_id=auditorium_id,
            version=version,
            status=DRAFT,
            rows=rows,
            cols=cols,
            seats=parsed,
            updated_at=stamp
        );
        assign_id(layout, layout_id);
        screen ++> layout;
        attach_to_tenant(layout, scope.tenant);
        flush_now();
    } except Exception as e {
        release(LAYOUT_VERSIONS, key, layout_id);
        raise e;
    } finally {
        restore(me);
    }
    on_commit(lambda { make_permanent(LAYOUT_VERSIONS, key, layout_id); });
    return {"ok": True, "layout": _view(layout)};
}

def _publish_layout(tenant: str, auditorium_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = on_shift(tenant);
    screen = _screen(scope, auditorium_id, CONFIGURE);
    lock = _lock_screen(auditorium_id);
    try {
        return _freeze_draft(scope, screen);
    } except Exception as e {
        release(LAYOUT_EDITS, auditorium_id, lock);
        raise e;
    }
}

def _freeze_draft(scope: TenantScope, screen: Auditorium) -> dict[str, any] {  # jac:ignore[W1037]
    # publish_layout's work, under the screen's edit lock.
    draft = _draft_of(layouts_of(scope.tenant, screen));
    if draft is None {
        raise Refused(
            "no_draft", "There are no unpublished changes to this screen's layout."
        );
    }
    problems = check_layout(draft.rows, draft.cols, draft.seats, for_publish=True);
    if problems {
        raise _invalid(problems);
    }
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        draft.status = PUBLISHED;
        draft.published_at = now().isoformat();
        flush_now();
    } finally {
        restore(me);
    }
    return {"ok": True, "layout": _view(draft)};
}

def _list_layouts(tenant: str, auditorium_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = on_shift(tenant);
    screen = _screen(scope, auditorium_id, READ);
    layouts = layouts_of(scope.tenant, screen);
    published = [
        l.version
        for l in layouts
        if l.status == PUBLISHED
    ];
    draft = _draft_of(layouts);
    return {
        "ok": True,
        "layouts": [_summary(l) for l in layouts],
        "published_version": published[-1] if published else None,
        "draft_version": draft.version if draft is not None else None
    };
}

def _get_layout(tenant: str, layout_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = on_shift(tenant);
    layout = find_layout(scope.tenant, layout_id);
    if layout is None {
        raise NotFound();
    }
    require(
        scope.ctx,
        READ,
        Resource(tenant_id=scope.ctx.tenant_id, venue_id=layout.venue_id)
    );
    return {"ok": True, "layout": _view(layout)};
}

def:priv save_layout(
    tenant: str,
    auditorium_id: str,
    rows: int,
    cols: int,
    seats: list[any]  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(
        lambda -> any { return _save_layout(tenant, auditorium_id, rows, cols, seats); }  # jac:ignore[W1037]
    );
}

def:priv publish_layout(tenant: str, auditorium_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _publish_layout(tenant, auditorium_id); });  # jac:ignore[W1037]
}

def:priv list_layouts(tenant: str, auditorium_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _list_layouts(tenant, auditorium_id); });  # jac:ignore[W1037]
}

def:priv get_layout(tenant: str, layout_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _get_layout(tenant, layout_id); });  # jac:ignore[W1037]
}
