"""P2.2: owner signup provisions a tenant atomically (architecture §92).

One call creates the tenant's service principal (ADR-0003), the Tenant, the OWNER staff
group and the owner's membership (ADR-0004), and holds the slug (ADR-0007). A failure
at any step must leave nothing behind: no tenant, no held slug, no stray principal.
"""

import os;
import time;
import from os { path }
import from tests.support.served { Served, served }

glob APP: str = path.join(
         path.dirname(path.dirname(path.abspath(__file__))), "apps", "signup_app.jac"
     ),
     FAULTS: str = "AFRICINEMAS_FAULTS",
     STEPS: list[str] = [
         "after_claim",
         "after_principal",
         "after_tenant",
         "after_group",
         "after_membership",
         "before_commit"
     ];

def _create(app: Served, who: str, name: str, slug: str) -> any {  # jac:ignore[W1037]
    return app.call(who, "create_cinema", {"name": name, "slug": slug});
}

test "signup creates the tenant, its principal, the owner group and the owner's membership" {
    app = served(APP, ["owner_a", "stranger"]);
    try {
        before = app.call("owner_a", "t_principals");
        made = _create(app, "owner_a", "Nova Cinemas", " Nova ");
        assert made["created"]
            and made["slug"] == "nova"
            and made["state"] == "configuring" , made;
        mine = app.call("owner_a", "my_cinemas");
        assert mine
            == [
                {
                    "tenant_id": made["tenant_id"],
                    "slug": "nova",
                    "name": "Nova Cinemas",
                    "state": "configuring",
                    "roles": ["owner"],
                    "access": "WRITE"
                }
            ] , mine;
        assert app.call("owner_a", "t_slug_holder", {"slug": "nova"})
            == made["tenant_id"];
        tenants = app.call("owner_a", "t_tenants", {"slug": "nova"});
        assert tenants == 1 , f"{tenants} tenant nodes";
        after = app.call("owner_a", "t_principals");
        assert after == before + 1 , f"principals {before} -> {after}";
        theirs = app.call("stranger", "my_cinemas");
        assert theirs == [] , theirs;
    } finally {
        app.close();
    }
}

test "the slug hold becomes permanent once signup commits" {
    os.environ["AFRICINEMAS_SIGNUP_SLUG_HOLD_S"] = "1";
    app = served(APP, ["owner_a", "owner_b"]);
    try {
        made = _create(app, "owner_a", "Nova Cinemas", "nova");
        time.sleep(1.5);
        assert app.call("owner_a", "t_slug_holder", {"slug": "nova"})
            == made["tenant_id"];
        refused = _create(app, "owner_b", "Other Nova", "nova");
        assert refused["error"]["code"] == "slug_taken" , refused;
    } finally {
        os.environ.pop("AFRICINEMAS_SIGNUP_SLUG_HOLD_S", None);
        app.close();
    }
}

test "a failure at any step leaves no tenant, no held slug and no stray principal" {
    app = served(APP, ["owner_a"]);
    try {
        before = app.call("owner_a", "t_principals");
        for step in STEPS {
            os.environ[FAULTS] = step;
            try {
                resp = app.post(
                    "owner_a", "create_cinema", {"name": "Nova Cinemas", "slug": "nova"}
                );
            } finally {
                os.environ.pop(FAULTS, None);
            }
            assert resp.status_code != 200 , f"{step}: the injected fault did not fail the request";
            assert app.call("owner_a", "t_tenants", {"slug": "nova"}) == 0 , f"{step}: a tenant was left";
            assert app.call("owner_a", "t_slug_holder", {"slug": "nova"}) is None , f"{step}: the slug stayed held";
            assert app.call("owner_a", "t_principals") == before , f"{step}: a principal was left";
            assert app.call("owner_a", "my_cinemas") == [] , f"{step}: a membership was left";
        }
        assert _create(app, "owner_a", "Nova Cinemas", "nova")["created"] , "a clean retry succeeds";
        # Guards the checks above against passing vacuously: principals are counted.
        assert app.call("owner_a", "t_principals") == before + 1;
    } finally {
        app.close();
    }
}

test "taken and invalid slugs get typed errors and create nothing" {
    app = served(APP, ["owner_a", "owner_b"]);
    try {
        _create(app, "owner_a", "Nova Cinemas", "nova");
        before = app.call("owner_b", "t_principals");
        taken = _create(app, "owner_b", "Nova Two", "NOVA");
        assert taken["created"] == False
            and taken["error"]["code"] == "slug_taken" , taken;
        bad = _create(app, "owner_b", "Admin Cinema", "admin");
        assert bad["error"]["code"] == "invalid_slug"
            and bad["error"]["reason"] == "reserved" , bad;
        unnamed = _create(app, "owner_b", "  ", "fresh-slug");
        assert unnamed["error"]["code"] == "invalid_name" , unnamed;
        assert app.call("owner_b", "t_principals") == before;
        assert app.call("owner_b", "my_cinemas") == [];
        assert app.call("owner_b", "t_slug_holder", {"slug": "fresh-slug"}) is None;
    } finally {
        app.close();
    }
}
