"""One-off (P14.1, owner decision 2026-10-22): the cinemas made before only active ones
were public stay public. Run once on a database from before 14.1:
    jac run scripts/activate_existing_cinemas.jac
Every cinema still being set up or waiting for review becomes active, as if approved;
others are left alone. It prints what it changed. New cinemas go live through the
platform's review (platform_approve_cinema), never this.
"""

import from core.claims { claims_in }
import from core.tenancy.registry { SLUG_NAMESPACE }
import from core.tenancy.open_cinema { tenant_by_id }
import from core.tenancy.state { TenantState }
import from core.tenancy.principal { node_id, act_as, restore, flush_now }

with entry {
    changed = 0;
    for (slug, tenant_id, _) in claims_in(SLUG_NAMESPACE) {
        cinema = tenant_by_id(str(tenant_id));
        if cinema is None or cinema.state not in ["configuring", "ready_for_go_live"] {
            continue;
        }
        me = node_id(root);
        act_as(cinema.principal_root_id);
        try {
            if cinema.state == "configuring" {
                cinema.move_to(TenantState.READY_FOR_GO_LIVE);
            }
            cinema.move_to(TenantState.ACTIVE);
            flush_now();
        } finally {
            restore(me);
        }
        print(f"{slug}: now active");
        changed += 1;
    }
    print(f"{changed} cinema(s) made active.");
}
