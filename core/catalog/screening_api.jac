"""Screenings (P3.5a, architecture §120, §121). Tenant-scoped endpoints, listed in
tests/isolation/registry.jac.

- A screening puts one of the cinema's movies on one of its screens at a time. It is
  created as a draft and pins the screen's latest published seat layout version, which
  it keeps when the layout changes later (P3.2). A screen with no published layout
  can't be scheduled.
- Screenings on a screen may not overlap: each keeps the screen busy for the movie's
  running time plus a cleaning buffer (screening_rules.jac). Creating or moving one takes
  the screen's schedule lock (an atomic claim, ADR-0007); a request that finds it
  taken is told the screen is busy. The lock alone isn't enough: a request can take it
  just after another released it while still reading the screen's screenings from
  before that commit. So each also bumps the screen's schedule_rev, making concurrent
  schedulings write the same record; the database re-runs the later one, which then
  sees the earlier screening (flush_now, JI-031).
- The lifecycle is screening_rules.jac; publishing (seat inventory and the storefront)
  is plan 3.5b.
- showtimes.read / .create / .update / .cancel apply at the screen's venue. Another
  cinema's ids answer not_found.
"""

import from datetime { datetime }
import from core.clock { now }
import from core.claims { claim, release }
import from core.authz.policy { Resource, require }
import from core.authz.context { NotFound, TenantScope, on_shift }
import from core.tenancy.groups { attach_to_tenant }
import from core.tenancy.principal {
    node_id,
    act_as,
    restore,
    flush_now,
    fresh_node_id
}
import from core.catalog.models { Auditorium, Screening, SeatLayout, PUBLISHED }
import from core.catalog.answers { Refused, answer }
import from core.catalog.venues {
    find_auditorium,
    find_movie,
    find_screening,
    layouts_of,
    screenings_of
}
import from core.catalog.screening_rules {
    ScreeningState,
    InvalidTransition,
    InvalidStart,
    transition,
    occupies_screen,
    can_reschedule,
    ends_at,
    overlaps,
    parse_start
}

glob READ: str = "showtimes.read",
     CREATE: str = "showtimes.create",
     UPDATE: str = "showtimes.update",
     CANCEL: str = "showtimes.cancel",
     SCHEDULE_LOCKS: str = "screen-schedule",
     LOCK_HOLD_S: int = 15;

def _at_venue(scope: TenantScope, action: str, venue_id: str) {
    require(
        scope.ctx, action, Resource(tenant_id=scope.ctx.tenant_id, venue_id=venue_id)
    );
}

def _screen(scope: TenantScope, auditorium_id: str, action: str) -> Auditorium {
    # The caller's screen, once they may do `action` at its venue.
    screen = find_auditorium(scope.tenant, auditorium_id);
    if screen is None {
        raise NotFound();
    }
    _at_venue(scope, action, screen.venue_id);
    return screen;
}

def _screening(scope: TenantScope, screening_id: str, action: str) -> Screening {
    found = find_screening(scope.tenant, screening_id);
    if found is None {
        raise NotFound();
    }
    _at_venue(scope, action, found.venue_id);
    return found;
}

def _view(scope: TenantScope, s: Screening) -> dict[str, any] {  # jac:ignore[W1037]
    movie = find_movie(scope.tenant, s.movie_id);
    return {
        "screening_id": node_id(s),
        "auditorium_id": s.auditorium_id,
        "venue_id": s.venue_id,
        "movie_id": s.movie_id,
        "movie_title": movie.title if movie is not None else "",
        "layout_id": s.layout_id,
        "layout_version": s.layout_version,
        "starts_at": s.starts_at,
        "ends_at": s.ends_at,
        "state": s.state
    };
}

def _start(text: str) -> datetime {
    try {
        return parse_start(text, now());
    } except InvalidStart as e {
        raise Refused(e.code, e.message);
    }
}

def _published_layout(scope: TenantScope, screen: Auditorium) -> SeatLayout {
    published = [
        l
        for l in layouts_of(scope.tenant, screen)
        if l.status == PUBLISHED
    ];
    if not published {
        raise Refused(
            "no_layout",
            f"Publish a seat layout for {screen.name} before scheduling screenings on it."
        );
    }
    return published[-1];
}

def _lock(screen: Auditorium) -> str {
    # The screen's schedule lock, held until this request commits (or fails, or
    # LOCK_HOLD_S passes). Returns the lock's owner id.
    owner = fresh_node_id();
    if claim(SCHEDULE_LOCKS, node_id(screen), owner, LOCK_HOLD_S) != owner {
        raise Refused(
            "screen_busy",
            f"Someone else is scheduling {screen.name} right now. Try again in a moment."
        );
    }
    on_commit(lambda { release(SCHEDULE_LOCKS, node_id(screen), owner); });
    return owner;
}

def _check_free(
    scope: TenantScope, screen: Auditorium, start: datetime, end: datetime, ignore: str
) {
    # Refuses if another screening keeps the screen busy at any time in [start, end).
    for other in screenings_of(scope.tenant, screen) {
        if node_id(other) == ignore
            or not occupies_screen(ScreeningState(other.state)) {
            continue;
        }
        if overlaps(
            start,
            end,
            datetime.fromisoformat(other.starts_at),
            datetime.fromisoformat(other.ends_at)
        ) {
            movie = find_movie(scope.tenant, other.movie_id);
            title = movie.title if movie is not None else "another screening";
            raise Refused(
                "overlap",
                f"{screen.name} already has {title} showing then (with cleaning time).",
                {
                    "screening_id": node_id(other),
                    "starts_at": other.starts_at,
                    "ends_at": other.ends_at
                }
            );
        }
    }
}

def _create_screening(
    tenant: str, auditorium_id: str, movie_id: str, starts_at: str
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = on_shift(tenant);
    screen = _screen(scope, auditorium_id, CREATE);
    movie = find_movie(scope.tenant, movie_id);
    if movie is None {
        raise NotFound();
    }
    start = _start(starts_at);
    end = ends_at(start, movie.runtime_minutes);
    layout = _published_layout(scope, screen);
    lock = _lock(screen);
    me = node_id(root);
    try {
        _check_free(scope, screen, start, end, "");
        stamp = now().isoformat();
        act_as(scope.tenant.principal_root_id);
        try {
            screening = Screening(
                tenant_id=scope.ctx.tenant_id,
                venue_id=screen.venue_id,
                auditorium_id=auditorium_id,
                movie_id=movie_id,
                layout_id=node_id(layout),
                layout_version=layout.version,
                starts_at=start.isoformat(),
                ends_at=end.isoformat(),
                state=ScreeningState.DRAFT.value,
                created_at=stamp,
                updated_at=stamp
            );
            screen ++> screening;
            attach_to_tenant(screening, scope.tenant);
            screen.schedule_rev += 1;  # makes concurrent schedulings clash (see models)
            flush_now();
        } finally {
            restore(me);
        }
    } except Exception as e {
        release(SCHEDULE_LOCKS, node_id(screen), lock);
        raise e;
    }
    return {"ok": True, "screening": _view(scope, screening)};
}

def _list_screenings(tenant: str, auditorium_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = on_shift(tenant);
    screen = _screen(scope, auditorium_id, READ);
    return {
        "ok": True,
        "screenings": [_view(scope, s) for s in screenings_of(scope.tenant, screen)]
    };
}

def _get_screening(tenant: str, screening_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = on_shift(tenant);
    return {
        "ok": True,
        "screening": _view(scope, _screening(scope, screening_id, READ))
    };
}

def _reschedule_screening(
    tenant: str, screening_id: str, starts_at: str
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = on_shift(tenant);
    screening = _screening(scope, screening_id, UPDATE);
    if not can_reschedule(ScreeningState(screening.state)) {
        raise Refused(
            "invalid_transition",
            "Only draft or scheduled screenings can be moved to another time."
        );
    }
    screen = find_auditorium(scope.tenant, screening.auditorium_id);
    movie = find_movie(scope.tenant, screening.movie_id);
    if screen is None or movie is None {
        raise NotFound();
    }
    start = _start(starts_at);
    end = ends_at(start, movie.runtime_minutes);
    lock = _lock(screen);
    me = node_id(root);
    try {
        _check_free(scope, screen, start, end, screening_id);
        act_as(scope.tenant.principal_root_id);
        try {
            screening.starts_at = start.isoformat();
            screening.ends_at = end.isoformat();
            screening.updated_at = now().isoformat();
            screen.schedule_rev += 1;  # makes concurrent schedulings clash (see models)
            flush_now();
        } finally {
            restore(me);
        }
    } except Exception as e {
        release(SCHEDULE_LOCKS, node_id(screen), lock);
        raise e;
    }
    return {"ok": True, "screening": _view(scope, screening)};
}

def _move_to(
    tenant: str, screening_id: str, action: str, target: ScreeningState
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = on_shift(tenant);
    screening = _screening(scope, screening_id, action);
    try {
        transition(ScreeningState(screening.state), target);
    } except InvalidTransition {
        raise Refused(
            "invalid_transition",
            f"A {screening.state.replace('_', ' ')} screening can't be {target.value.replace(
                '_', ' '
            )}."
        );
    }
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        screening.state = target.value;
        screening.updated_at = now().isoformat();
        flush_now();
    } finally {
        restore(me);
    }
    return {"ok": True, "screening": _view(scope, screening)};
}

def:priv create_screening(
    tenant: str, auditorium_id: str, movie_id: str, starts_at: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(
        lambda -> any { return _create_screening(  # jac:ignore[W1037]
            tenant, auditorium_id, movie_id, starts_at
        ); }
    );
}

def:priv list_screenings(tenant: str, auditorium_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _list_screenings(tenant, auditorium_id); });  # jac:ignore[W1037]
}

def:priv get_screening(tenant: str, screening_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _get_screening(tenant, screening_id); });  # jac:ignore[W1037]
}

def:priv reschedule_screening(
    tenant: str, screening_id: str, starts_at: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(
        lambda -> any { return _reschedule_screening(tenant, screening_id, starts_at); }  # jac:ignore[W1037]
    );
}

def:priv schedule_screening(tenant: str, screening_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(
        lambda -> any { return _move_to(  # jac:ignore[W1037]
            tenant, screening_id, UPDATE, ScreeningState.SCHEDULED
        ); }
    );
}

def:priv cancel_screening(tenant: str, screening_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(
        lambda -> any { return _move_to(  # jac:ignore[W1037]
            tenant, screening_id, CANCEL, ScreeningState.CANCELLED
        ); }
    );
}
