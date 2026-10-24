"""One-off (P14.5a): cinemas approved before the date was kept on the cinema get it now.
    jac run scripts/copy_verified_dates.jac
For each cinema whose verification was approved, copies the approval date onto the
cinema (Tenant.verified_at), where the back office and storefront read it for the
Verified badge. A cinema made public with the plain Approve button (no review) has no
approved verification, so it's left alone: it isn't verified. It prints what it did.
"""

import from core.claims { claims_in }
import from core.tenancy.registry { SLUG_NAMESPACE }
import from core.tenancy.open_cinema { tenant_by_id }
import from core.tenancy.principal { node_id, act_as, restore, flush_now }
import from core.tenancy.verification { record_of }

with entry {
    changed = 0;
    for (slug, tenant_id, _) in claims_in(SLUG_NAMESPACE) {
        cinema = tenant_by_id(str(tenant_id));
        if cinema is None or cinema.verified_at {
            continue;
        }
        kept = record_of(cinema);
        print(f"{slug}: verification {kept['status']}");
        if kept["status"] != "approved" or not kept["approved_at"] {
            continue;
        }
        me = node_id(root);
        act_as(cinema.principal_root_id);
        try {
            cinema.verified_at = kept["approved_at"];
            flush_now();
        } finally {
            restore(me);
        }
        print(f"{slug}: verified on {kept['approved_at'][:10]}");
        changed += 1;
    }
    print(f"{changed} cinema(s) given their Verified date.");
}
