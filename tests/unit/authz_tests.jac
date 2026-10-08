"""P2.3: roles, permissions and authorize() (architecture §14, §15, §129, §130).

The MATRIX below is the reviewed specification of who may do what; the policy table in
core/authz/policy.jac must match it cell for cell. Roles are deliberately not a ladder:
Finance can refund but not manage staff; a tenant admin manages staff but doesn't see
revenue; only the owner can delete the tenant or change payment settings.
"""

import from core.authz.policy {
    PERMISSIONS,
    ROLES,
    VENUE_SCOPABLE_ROLES,
    ROLE_PERMISSIONS,
    RoleAssignment,
    AuthContext,
    Resource,
    Forbidden,
    authorize,
    require
}

glob READS: set[str] = {
         "movies.read",
         "showtimes.read",
         "seats.read",
         "venues.read",
         "bookings.read",
         "payments.read",
         "financial_reports.read",
         "employees.read",
         "audit.read"
     },
     MATRIX: dict[str, set[str]] = {
         "owner": set(PERMISSIONS),
         "tenant_admin": {
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
             "employees.read",
             "employees.invite",
             "employees.disable",
             "employees.assign_roles",
             "tenant.settings.update"
         },
         "general_manager": {
             "movies.read",
             "showtimes.read",
             "showtimes.create",
             "showtimes.update",
             "showtimes.cancel",
             "seats.read",
             "venues.read",
             "bookings.read",
             "bookings.create",
             "bookings.cancel",
             "tickets.issue",
             "tickets.invalidate",
             "tickets.scan",
             "payments.read",
             "financial_reports.read",
             "employees.read"
         },
         "finance_manager": {
             "movies.read",
             "showtimes.read",
             "bookings.read",
             "payments.read",
             "payments.refund",
             "payments.reconcile",
             "financial_reports.read"
         },
         "box_office_manager": {
             "movies.read",
             "showtimes.read",
             "seats.read",
             "venues.read",
             "bookings.read",
             "bookings.create",
             "bookings.cancel",
             "tickets.issue",
             "tickets.invalidate",
             "tickets.scan",
             "payments.read",
             "employees.read"
         },
         "box_office_agent": {
             "movies.read",
             "showtimes.read",
             "seats.read",
             "venues.read",
             "bookings.read",
             "bookings.create",
             "tickets.issue"
         },
         "content_manager": {
             "movies.read",
             "movies.create",
             "movies.update",
             "movies.publish",
             "showtimes.read",
             "showtimes.create",
             "showtimes.update",
             "seats.read",
             "venues.read"
         },
         "usher": {"showtimes.read", "venues.read", "bookings.read", "tickets.scan"},
         "auditor": READS,
         "it_admin": {
             "venues.read",
             "seats.read",
             "employees.read",
             "tenant.settings.update"
         }
     };

def _ctx(tenant: str, *assignments: RoleAssignment) -> AuthContext {
    return AuthContext(
        tenant_id=tenant, member_root_id="m-1", assignments=list(assignments)
    );
}

test "the role table matches the reviewed matrix, cell by cell" {
    assert set(ROLES) == set(MATRIX.keys()) , sorted(set(ROLES) ^ set(MATRIX.keys()));
    for role in ROLES {
        for perm in PERMISSIONS {
            granted = authorize(
                _ctx("t-a", RoleAssignment(role=role)),
                perm,
                Resource(tenant_id="t-a", venue_id="v-1")
            );
            assert granted == (perm in MATRIX[role]) , f"{role} / {perm}: policy says {granted}";
        }
    }
}

test "every granted permission exists, and the owner holds all of them" {
    for (role, perms) in ROLE_PERMISSIONS.items() {
        assert perms <= set(PERMISSIONS) , f"{role}: unknown {perms
            - set(PERMISSIONS)}";
    }
    assert ROLE_PERMISSIONS["owner"] == set(PERMISSIONS);
}

test "sensitive actions belong to the owner alone" {
    for perm in ["tenant.delete", "tenant.payment_settings.update"] {
        holders = sorted(
            [
                r
                for r in ROLES
                if perm in ROLE_PERMISSIONS[r]
            ]
        );
        assert holders == ["owner"] , f"{perm}: {holders}";
    }
    assert "payments.refund" not in ROLE_PERMISSIONS["tenant_admin"] , "admin need not touch money";
    assert "employees.assign_roles" not in ROLE_PERMISSIONS["finance_manager"];
    assert all(p in READS for p in ROLE_PERMISSIONS["auditor"]) , "auditors only read";
}

test "unknown actions are denied, even for the owner" {
    owner = _ctx("t-a", RoleAssignment(role="owner"));
    for action in ["tenant.destroy_everything", "", "movies.*", "MOVIES.READ"] {
        assert not authorize(owner, action, Resource(tenant_id="t-a")) , action;
    }
}

test "a member without roles can do nothing" {
    nobody = _ctx("t-a");
    assert not any(
        authorize(nobody, p, Resource(tenant_id="t-a", venue_id="v-1"))
        for p in PERMISSIONS
    );
}

test "another tenant's resource is denied, even for the owner" {
    owner = _ctx("t-a", RoleAssignment(role="owner"));
    assert not authorize(owner, "movies.read", Resource(tenant_id="t-b"));
    assert authorize(owner, "movies.read", Resource(tenant_id="t-a"));
}

test "a venue-scoped role is denied other venues and tenant-wide resources" {
    agent_v1 = _ctx("t-a", RoleAssignment(role="box_office_agent", venue_ids=["v-1"]));
    assert authorize(
        agent_v1, "bookings.create", Resource(tenant_id="t-a", venue_id="v-1")
    );
    assert not authorize(
        agent_v1, "bookings.create", Resource(tenant_id="t-a", venue_id="v-2")
    );
    assert not authorize(agent_v1, "bookings.read", Resource(tenant_id="t-a")) , "no venue: tenant-wide";
    unscoped = _ctx("t-a", RoleAssignment(role="box_office_agent"));
    assert authorize(
        unscoped, "bookings.create", Resource(tenant_id="t-a", venue_id="v-2")
    );
    assert authorize(unscoped, "bookings.read", Resource(tenant_id="t-a"));
}

test "each assignment counts only within its own scope" {
    mixed = _ctx(
        "t-a",
        RoleAssignment(role="usher", venue_ids=["v-1"]),
        RoleAssignment(role="box_office_agent", venue_ids=["v-2"])
    );
    assert authorize(mixed, "tickets.scan", Resource(tenant_id="t-a", venue_id="v-1"));
    assert not authorize(
        mixed, "tickets.scan", Resource(tenant_id="t-a", venue_id="v-2")
    );
    assert authorize(
        mixed, "bookings.create", Resource(tenant_id="t-a", venue_id="v-2")
    );
    assert not authorize(
        mixed, "bookings.create", Resource(tenant_id="t-a", venue_id="v-1")
    );
}

test "only operational roles can be limited to venues" {
    assert set(VENUE_SCOPABLE_ROLES)
        == {"general_manager", "box_office_manager", "box_office_agent", "usher"};
    for role in ROLES {
        if role not in VENUE_SCOPABLE_ROLES {
            refused = False;
            try {
                RoleAssignment(role=role, venue_ids=["v-1"]);
            } except ValueError {
                refused = True;
            }
            assert refused , f"{role} must be tenant-wide";
        }
    }
    refused = False;
    try {
        RoleAssignment(role="projectionist");
    } except ValueError {
        refused = True;
    }
    assert refused , "unknown roles are refused";
}

test "require raises a typed Forbidden naming the action" {
    usher = _ctx("t-a", RoleAssignment(role="usher"));
    require(usher, "tickets.scan", Resource(tenant_id="t-a", venue_id="v-1"));
    raised = False;
    try {
        require(usher, "payments.refund", Resource(tenant_id="t-a", venue_id="v-1"));
    } except Forbidden as e {
        raised = True;
        assert e.action == "payments.refund" and e.code == "forbidden";
    }
    assert raised;
}

test "the role signup gives the owner is the policy's owner role" {
    import from core.tenancy.models { ROLE_OWNER }
    assert ROLE_OWNER in ROLES and ROLE_PERMISSIONS[ROLE_OWNER] == set(PERMISSIONS);
}
