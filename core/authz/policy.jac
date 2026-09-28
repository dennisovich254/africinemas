"""Tenant roles, permissions and the one authorization decision (ADR-0008).

Architecture §14/§15/§129/§130: RBAC + tenant scope + venue scope, deny by default,
decided in one place. Graph grants already keep tenants apart (ADR-0004); this layer
decides what a member may do inside their tenant. Roles are permission sets, not a
ladder. Pure logic: the caller builds the AuthContext from the graph (P2.4).
"""

glob PERMISSIONS: list[str] = [
         "movies.read",
         "movies.create",
         "movies.update",
         "movies.publish",
         "showtimes.read",
         "showtimes.create",
         "showtimes.update",
         "showtimes.cancel",
         "seats.read",
         "seats.configure",
         "venues.read",
         "venues.configure",
         "bookings.read",
         "bookings.create",
         "bookings.cancel",
         "tickets.issue",
         "tickets.invalidate",
         "tickets.scan",
         "payments.read",
         "payments.refund",
         "payments.reconcile",
         "financial_reports.read",
         "employees.read",
         "employees.invite",
         "employees.disable",
         "employees.assign_roles",
         "tenant.settings.update",
         "tenant.payment_settings.update",
         "tenant.delete"
     ],
     _CATALOGUE_READ: set[str] = {"movies.read", "showtimes.read"},
     _FLOOR_READ: set[str] = {"seats.read", "venues.read"},
     _MOVIES_ALL: set[str] = {
         "movies.read",
         "movies.create",
         "movies.update",
         "movies.publish"
     },
     _SHOWTIMES_ALL: set[str] = {
         "showtimes.read",
         "showtimes.create",
         "showtimes.update",
         "showtimes.cancel"
     },
     _BOOKINGS_ALL: set[str] = {"bookings.read", "bookings.create", "bookings.cancel"},
     _TICKETS_ALL: set[str] = {"tickets.issue", "tickets.invalidate", "tickets.scan"},
     _STAFF_ALL: set[str] = {
         "employees.read",
         "employees.invite",
         "employees.disable",
         "employees.assign_roles"
     },
     _MONEY_ALL: set[str] = {
         "payments.read",
         "payments.refund",
         "payments.reconcile",
         "financial_reports.read"
     },
     ROLE_PERMISSIONS: dict[str, set[str]] = {
         "owner": set(PERMISSIONS),
         # Runs the cinema's setup and staff; doesn't handle money or the tenant itself.
         "tenant_admin": _MOVIES_ALL
             | _SHOWTIMES_ALL
             | {"seats.read", "seats.configure", "venues.read", "venues.configure"}
             | _BOOKINGS_ALL
             | _TICKETS_ALL
             | _STAFF_ALL
             | {"tenant.settings.update"},
         "general_manager": {"movies.read"}
             | _SHOWTIMES_ALL
             | _FLOOR_READ
             | _BOOKINGS_ALL
             | _TICKETS_ALL
             | {"payments.read", "financial_reports.read", "employees.read"},
         "finance_manager": _CATALOGUE_READ | {"bookings.read"} | _MONEY_ALL,
         "box_office_manager": _CATALOGUE_READ
             | _FLOOR_READ
             | _BOOKINGS_ALL
             | _TICKETS_ALL
             | {"payments.read", "employees.read"},
         "box_office_agent": _CATALOGUE_READ
             | _FLOOR_READ
             | {"bookings.read", "bookings.create", "tickets.issue"},
         "content_manager": _MOVIES_ALL
             | {"showtimes.read", "showtimes.create", "showtimes.update"}
             | _FLOOR_READ,
         "usher": {"showtimes.read", "venues.read", "bookings.read", "tickets.scan"},
         "auditor": _CATALOGUE_READ
             | _FLOOR_READ
             | {
                 "bookings.read",
                 "payments.read",
                 "financial_reports.read",
                 "employees.read"
             },
         "it_admin": _FLOOR_READ | {"employees.read", "tenant.settings.update"}
     },
     ROLES: list[str] = list(ROLE_PERMISSIONS.keys()),
     # Front-of-house roles that can be limited to specific venues; the rest act
     # tenant-wide (money, staff, content and the tenant's settings aren't per venue).
     VENUE_SCOPABLE_ROLES: list[str] = [
         "general_manager",
         "box_office_manager",
         "box_office_agent",
         "usher"
     ];

obj RoleAssignment {
    # One role held by a member; `venue_ids` None means tenant-wide.
    has role: str,
        venue_ids: list[str] | None = None;

    def postinit {
        if self.role not in ROLE_PERMISSIONS {
            raise ValueError(f"unknown role: {self.role!r}");
        }
        if self.venue_ids is not None and self.role not in VENUE_SCOPABLE_ROLES {
            raise ValueError(f"{self.role} can't be limited to venues");
        }
    }

    def covers(resource: Resource) -> bool {
        if self.venue_ids is None {
            return True;
        }
        # A venue-scoped role never reaches tenant-wide resources.
        return resource.venue_id is not None and resource.venue_id in self.venue_ids;
    }
}

obj AuthContext {
    # Who is acting, in which tenant, with which roles (built server-side, P2.4).
    has tenant_id: str,
        member_root_id: str,
        assignments: list[RoleAssignment] = [];
}

obj Resource {
    # What is being acted on: its tenant and, for venue-bound things, its venue.
    has tenant_id: str,
        venue_id: str | None = None;
}

class Forbidden(PermissionError) {
    def init(self: Forbidden, action: str) {
        super.init(f"not allowed: {action}");
        self.action = action;
        self.code = "forbidden";
    }
}

def authorize(ctx: AuthContext, action: str, resource: Resource) -> bool {
    if action not in PERMISSIONS {
        return False;
    }
    if resource.tenant_id != ctx.tenant_id {
        return False;
    }
    return any(
        action in ROLE_PERMISSIONS[a.role] and a.covers(resource)
        for a in ctx.assignments
    );
}

def require(ctx: AuthContext, action: str, resource: Resource) {
    if not authorize(ctx, action, resource) {
        raise Forbidden(action);
    }
}

def role_key(role: str, venue_id: str) -> str {
    # How a role is stored on a membership: "usher" or "usher@venue-1". Raises
    # ValueError for an unknown role or a venue on a tenant-wide role.
    RoleAssignment(role=role, venue_ids=[venue_id] if venue_id else None);
    return f"{role}@{venue_id}" if venue_id else role;
}

def assignments_from_keys(keys: list[str]) -> list[RoleAssignment] {
    # Stored role keys -> assignments; one per role, merging its venues. A tenant-wide
    # key for a role wins over venue keys for the same role.
    venues_by_role: dict[str, list[str] | None] = {};
    for key in keys {
        (role, _, venue) = key.partition("@");
        if not venue {
            venues_by_role[role] = None;
        } elif role not in venues_by_role {
            venues_by_role[role] = [venue];
        } elif venues_by_role[role] is not None {
            venues_by_role[role] = sorted(set(venues_by_role[role] + [venue]));
        }
    }
    return [
        RoleAssignment(role=role, venue_ids=venues)
        for (role, venues) in sorted(venues_by_role.items())
    ];
}

def can_grant(ctx: AuthContext, role: str) -> bool {
    # No privilege escalation: an actor may grant (or take away) a role only if their
    # own tenant-wide roles already hold every permission it carries.
    held: set[str] = set();
    for a in ctx.assignments {
        if a.venue_ids is None {
            held = held | ROLE_PERMISSIONS[a.role];
        }
    }
    return role in ROLE_PERMISSIONS and ROLE_PERMISSIONS[role] <= held;
}
