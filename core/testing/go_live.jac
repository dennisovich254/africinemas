"""Test-only: making a cinema live (P14.1), for the test apps (payment_app.jac and its
like, and the real-server tests' apps, which copy core/), never main.jac:
tests/unit/no_test_code_in_main_tests.jac fails if main.jac imports core.testing.

Only an active cinema is public, and every storefront test starts with a cinema that's
still being set up. Production makes one live through the platform's review
(platform_approve_cinema); tests that aren't about the review use this instead.
"""

import from core.tenancy.open_cinema { tenant_by_id }
import from core.tenancy.registry { lookup_slug }
import from core.tenancy.state { TenantState }
import from core.tenancy.principal { node_id, act_as, restore, flush_now }

def:pub t_go_live(slug: str) -> bool {
    tenant_id = lookup_slug(slug);
    cinema = tenant_by_id(tenant_id) if tenant_id else None;
    if cinema is None {
        return False;
    }
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        if cinema.state == "configuring" {
            cinema.move_to(TenantState.READY_FOR_GO_LIVE);
        }
        if cinema.state == "ready_for_go_live" {
            cinema.move_to(TenantState.ACTIVE);
        }
        flush_now();
    } finally {
        restore(me);
    }
    return cinema.state == "active";
}
