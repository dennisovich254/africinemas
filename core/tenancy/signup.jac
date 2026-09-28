"""Owner signup: atomic tenant provisioning (P2.2, architecture §92).

`create_cinema` runs for a signed-in owner and, in one request:
1. validates the name and slug;
2. picks the tenant's id and claims the slug for it provisionally (ADR-0007): a taken
   slug is refused here, before anything is created;
3. creates the tenant's service principal (ADR-0003);
4. as the principal: creates the Tenant and its OWNER staff group, with grants;
5. adds the owner to that group (ADR-0004);
6. moves the tenant to CONFIGURING.

Graph work rolls back with the request if anything fails. The slug claim and the
principal user live outside the graph transaction, so a failure releases and deletes
them explicitly, and the claim only becomes permanent in on_commit. PROVISIONING is
therefore never visible: a tenant either commits as CONFIGURING or doesn't exist.
"""

import os;
import from uuid { UUID }
import from jaclang { JacRuntime as Jac }
import from core.clock { now }
import from core.faults { checkpoint }
import from core.tenancy.models { Tenant, StaffGroup, MemberOf, ForTenant, ROLE_OWNER }
import from core.tenancy.state { TenantState }
import from core.tenancy.slugs { InvalidSlug, validate_slug }
import from core.tenancy.registry {
    claim_slug,
    lookup_slug,
    make_slug_permanent,
    release_slug
}
import from core.tenancy.membership { join_group }
import from core.tenancy.principal {
    Principal,
    node_id,
    access_level,
    create_principal,
    delete_principal,
    fresh_node_id,
    assign_id,
    act_as,
    restore,
    flush_now
}

glob NAME_MAX: int = 80,
     SLUG_HOLD_ENV: str = "AFRICINEMAS_SIGNUP_SLUG_HOLD_S",
     SLUG_HOLD_DEFAULT_S: int = 900;

def _refused(
    code: str, message: str, reason: str = ""
) -> dict[str, bool | str | dict[str, str]] {
    return {
        "created": False,
        "error": {"code": code, "reason": reason, "message": message}
    };
}

def _slug_hold_s -> int {
    return int(os.environ.get(SLUG_HOLD_ENV, str(SLUG_HOLD_DEFAULT_S)));
}

def _provision(
    tenant_id: str, name: str, slug: str, principal: Principal, owner: str
) -> Tenant {
    act_as(principal.root_id);
    try {
        tenant = Tenant(
            slug=slug,
            name=name,
            principal_root_id=principal.root_id,
            created_at=now().isoformat()
        );
        assign_id(tenant, tenant_id);
        root ++> tenant;
        checkpoint("after_tenant");
        group = StaffGroup(tenant_id=tenant_id, role=ROLE_OWNER);
        root ++> group;
        group +>:ForTenant:+> tenant;
        group_id = UUID(node_id(group));
        # Members traverse through the group, so it grants READ on itself (ADR-0004).
        Jac.allow_group(group, group_id, AccessLevel.READ);  # jac:ignore[E1053]
        Jac.allow_group(tenant, group_id, AccessLevel.WRITE);  # jac:ignore[E1053]
        flush_now();
        checkpoint("after_group");
    } finally {
        restore(owner);
    }
    join_group(principal.root_id, group);
    checkpoint("after_membership");
    act_as(principal.root_id);
    try {
        tenant.move_to(TenantState.CONFIGURING);
        flush_now();
    } finally {
        restore(owner);
    }
    return tenant;
}

def:priv create_cinema(name: str, slug: str) -> dict[str, bool | str | dict[str, str]] {
    clean_name = name.strip();
    if not clean_name or len(clean_name) > NAME_MAX {
        return _refused(
            "invalid_name", f"Enter a cinema name of 1 to {NAME_MAX} characters."
        );
    }
    try {
        wanted = validate_slug(slug);
    } except InvalidSlug as e {
        return _refused("invalid_slug", str(e), e.reason);
    }
    if lookup_slug(wanted) is not None {
        return _refused(
            "slug_taken", f"'{wanted}' is already taken. Choose another name."
        );
    }
    owner = node_id(root);
    tenant_id = fresh_node_id();
    if claim_slug(wanted, tenant_id, _slug_hold_s()) != tenant_id {
        return _refused(
            "slug_taken", f"'{wanted}' is already taken. Choose another name."
        );
    }
    principal: Principal | None = None;
    try {
        checkpoint("after_claim");
        principal = create_principal(wanted);
        checkpoint("after_principal");
        tenant = _provision(tenant_id, clean_name, wanted, principal, owner);
        checkpoint("before_commit");
    } except Exception as e {
        # Graph work rolls back with the request; undo what lives outside it.
        restore(owner);
        release_slug(wanted, tenant_id);
        if principal is not None {
            delete_principal(principal.user_id);
        }
        raise e;
    }
    on_commit(lambda { make_slug_permanent(wanted, tenant_id); });
    return {
        "created": True,
        "tenant_id": tenant_id,
        "slug": wanted,
        "state": tenant.state
    };
}

def:priv my_cinemas -> list[dict[str, str]] {
    # The cinemas the caller is staff of, with their role there.
    found: list[dict[str, str]] = [];
    for g in [root->:MemberOf:->[?:StaffGroup]] {
        for t in [g->:ForTenant:->[?:Tenant]] {
            found.append(
                {
                    "tenant_id": node_id(t),
                    "slug": t.slug,
                    "name": t.name,
                    "state": t.state,
                    "role": g.role,
                    "access": access_level(t)
                }
            );
        }
    }
    return found;
}
