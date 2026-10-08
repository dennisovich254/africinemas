"""JI-042: the read tier is off for every app (core/tenancy/principal.jac).

With it on, a request the process hasn't seen write for a while runs read-only and is
re-run from the start at its first write; after a commit part-way (a sale, a scan) that
repeats work already done. Importing the principal module, as every app does, turns it
off.
"""

import from core.tenancy.principal { READ_TIER_OFF }
import from jaclang.server.session { ro_units_enabled }

test "importing the principal module turns Jac's read tier off" {
    assert READ_TIER_OFF;
    assert not ro_units_enabled();
}
