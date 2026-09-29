"""Looking up a cinema's venues, auditoriums, seat layouts, movies and screenings by id
(P3.1-P3.5a), and the screenings that hang off them.

Ids arrive from clients (the setup endpoints, staff invitations and role changes), so
every use checks the node exists and belongs to the cinema before relying on it: each
lookup answers None for another cinema's node, a node of another kind, or a bad id.
"""

import from core.tenancy.models { Tenant, Membership }
import from core.tenancy.membership { records_of }
import from core.tenancy.principal { node_id, act_as, restore }
import from core.catalog.models { Venue, Auditorium, SeatLayout, Movie, Screening }

def _read(tenant: Tenant, node_ref: str) -> any {  # jac:ignore[W1037]
    # The node with id `node_ref`, read as `tenant`'s principal; None if there's none or
    # the id isn't valid.
    if not node_ref {
        return None;
    }
    me = node_id(root);
    act_as(tenant.principal_root_id);
    try {
        found: any = jobj(node_ref);  # jac:ignore[W1037]
    } except Exception {
        found = None;
    } finally {
        restore(me);
    }
    return found;
}

def find_auditorium(tenant: Tenant, auditorium_id: str) -> Auditorium | None {
    # `tenant`'s auditorium with this id, or None (as find_venue).
    found = _read(tenant, auditorium_id);
    if not isinstance(found, Auditorium) or found.tenant_id != node_id(tenant) {
        return None;
    }
    return found as Auditorium;
}

def find_layout(tenant: Tenant, layout_id: str) -> SeatLayout | None {
    # `tenant`'s seat layout version with this id, or None (as find_venue).
    found = _read(tenant, layout_id);
    if not isinstance(found, SeatLayout) or found.tenant_id != node_id(tenant) {
        return None;
    }
    return found as SeatLayout;
}

def find_movie(tenant: Tenant, movie_id: str) -> Movie | None {
    # `tenant`'s movie with this id, or None (as find_venue).
    found = _read(tenant, movie_id);
    if not isinstance(found, Movie) or found.tenant_id != node_id(tenant) {
        return None;
    }
    return found as Movie;
}

def find_screening(tenant: Tenant, screening_id: str) -> Screening | None {
    # `tenant`'s screening with this id, or None (as find_venue).
    found = _read(tenant, screening_id);
    if not isinstance(found, Screening) or found.tenant_id != node_id(tenant) {
        return None;
    }
    return found as Screening;
}

def screenings_of(tenant: Tenant, auditorium: Auditorium) -> list[Screening] {
    # Every screening on `auditorium`, any state, earliest first.
    me = node_id(root);
    act_as(tenant.principal_root_id);
    try {
        found = [auditorium-->[?:Screening]];
    } finally {
        restore(me);
    }
    return sorted(found, key=lambda (s: Screening) -> str { return s.starts_at; });  # jac:ignore[W1037]
}

def screenings_of_movie(tenant: Tenant, movie_id: str) -> list[Screening] {
    # Every screening of the movie, on any of the cinema's screens.
    me = node_id(root);
    act_as(tenant.principal_root_id);
    try {
        found: list[Screening] = [];
        for venue in [tenant-->[?:Venue]] {
            for screen in [venue-->[?:Auditorium]] {
                for s in [screen-->[?:Screening]] {
                    if s.movie_id == movie_id {
                        found.append(s);
                    }
                }
            }
        }
    } finally {
        restore(me);
    }
    return found;
}

def version_key(auditorium_id: str, version: int) -> str {
    # The LAYOUT_VERSIONS claim key for one version of a screen's layout.
    return f"{auditorium_id}:{version}";
}

def layouts_of(tenant: Tenant, auditorium: Auditorium) -> list[SeatLayout] {
    # Every layout version of `auditorium`, oldest first.
    me = node_id(root);
    act_as(tenant.principal_root_id);
    try {
        found = [auditorium-->[?:SeatLayout]];
    } finally {
        restore(me);
    }
    return sorted(found, key=lambda (l: SeatLayout) -> int { return l.version; });  # jac:ignore[W1037]
}

def find_venue(tenant: Tenant, venue_id: str) -> Venue | None {
    # `tenant`'s venue with id `venue_id`, or None if there's no such venue at this
    # cinema (including another cinema's venue and ids that aren't valid).
    found = _read(tenant, venue_id);
    if not isinstance(found, Venue) or found.tenant_id != node_id(tenant) {
        return None;
    }
    return found as Venue;
}

def staff_at(tenant: Tenant, venue_id: str) -> list[Membership] {
    # Members of `tenant`, active or disabled, holding any role limited to `venue_id`.
    me = node_id(root);
    act_as(tenant.principal_root_id);
    try {
        records = records_of(tenant);
    } finally {
        restore(me);
    }
    return [
        m
        for m in records
        if any(key.partition("@")[2] == venue_id for key in m.roles)
    ];
}
