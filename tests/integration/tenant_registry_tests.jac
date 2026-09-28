"""P2.1: the control-plane slug registry (in-process app).

`claim_slug(slug, tenant_id)` records the slug for the tenant unless another tenant
holds it, and returns whoever holds it afterwards (an atomic claim, ADR-0007).
"""

import from os { path }
import from tests.support.served { served }

glob APP: str = path.join(
         path.dirname(path.dirname(path.abspath(__file__))), "apps", "tenancy_app.jac"
     );

test "a free slug is claimed by the first tenant, and the claim is idempotent" {
    app = served(APP, ["anyone"]);
    try {
        assert app.call("anyone", "t_claim", {"slug": "nova", "tenant_id": "t-a"})
            == {"owner": "t-a"};
        assert app.call("anyone", "t_claim", {"slug": "nova", "tenant_id": "t-a"})
            == {"owner": "t-a"};
        assert app.call("anyone", "t_lookup", {"slug": "nova"}) == "t-a";
    } finally {
        app.close();
    }
}

test "a taken slug stays with its owner" {
    app = served(APP, ["anyone"]);
    try {
        app.call("anyone", "t_claim", {"slug": "nova", "tenant_id": "t-a"});
        assert app.call("anyone", "t_claim", {"slug": "nova", "tenant_id": "t-b"})
            == {"owner": "t-a"};
    } finally {
        app.close();
    }
}

test "slugs are matched after normalising, and invalid ones are refused" {
    app = served(APP, ["anyone"]);
    try {
        app.call("anyone", "t_claim", {"slug": "Nova", "tenant_id": "t-a"});
        assert app.call("anyone", "t_lookup", {"slug": " NOVA "}) == "t-a";
        assert app.call("anyone", "t_claim", {"slug": "admin", "tenant_id": "t-a"})
            == {"error": "reserved"};
        assert app.call("anyone", "t_lookup", {"slug": "unknown"}) is None;
    } finally {
        app.close();
    }
}
