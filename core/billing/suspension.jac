"""Suspending a cinema for an unpaid invoice, and reinstating it (P15.5, ADR-0084).

Only ever done by a person (platform staff with platform.suspend), never by a job:
core/billing/billing_api.jac checks the invoice is more than GRACE_DAYS overdue and
not disputed. Suspended, the cinema is no longer public (open_cinema), its storefront
says "This cinema isn't available right now", and require_live refuses new orders and
payments online and at the counter. Its back office stays open, saying why, so it can
pay. Payments already under way still settle: the money was taken.
"""

import from core.clock { now }
import from core.tenancy.models { Tenant }
import from core.tenancy.state { TenantState }
import from core.tenancy.principal { node_id, act_as, restore, flush_now }

def set_suspension(cinema: Tenant, on: bool, reason: str, who: str) {
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        cinema.move_to(TenantState.SUSPENDED if on else TenantState.ACTIVE);
        cinema.suspended_at = now().isoformat() if on else "";
        cinema.suspended_reason = reason if on else "";
        cinema.suspended_by = who if on else "";
        flush_now();
    } finally {
        restore(me);
    }
}
