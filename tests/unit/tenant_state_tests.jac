"""Tenant lifecycle (architecture §92-§94, aligned in P2.2).

PROVISIONING -> CONFIGURING (signup done) -> READY_FOR_GO_LIVE (checklist done)
-> ACTIVE (go-live gate). ACTIVE <-> SUSPENDED. ACTIVE, SUSPENDED or CONFIGURING
-> CLOSING (cooling-off) -> DELETED, which is final; closing can be cancelled back
to ACTIVE or CONFIGURING. READY_FOR_GO_LIVE can return to CONFIGURING.
"""

import from core.tenancy.state { TenantState, InvalidTransition, ALLOWED, transition }

glob ALLOWED_PAIRS: list[tuple[str, str]] = [
         ("provisioning", "configuring"),
         ("configuring", "ready_for_go_live"),
         ("configuring", "closing"),
         ("ready_for_go_live", "active"),
         ("ready_for_go_live", "configuring"),
         ("active", "suspended"),
         ("active", "closing"),
         ("suspended", "active"),
         ("suspended", "closing"),
         ("closing", "deleted"),
         ("closing", "active"),
         ("closing", "configuring")
     ];

test "exactly the documented transitions are allowed" {
    pairs = sorted([(a.value, b.value) for a in TenantState for b in ALLOWED[a]]);
    assert pairs == sorted(ALLOWED_PAIRS) , pairs;
    for (a, b) in ALLOWED_PAIRS {
        assert transition(TenantState(a), TenantState(b)) == TenantState(b) , f"{a} -> {b}";
    }
}

test "every other transition is refused" {
    for current in TenantState {
        for target in TenantState {
            if target not in ALLOWED[current] {
                refused = False;
                try {
                    transition(current, target);
                } except InvalidTransition {
                    refused = True;
                }
                assert refused , f"{current.value} -> {target.value} should be refused";
            }
        }
    }
}

test "deleted is final and staying put is not a transition" {
    assert ALLOWED[TenantState.DELETED] == set();
    for state in TenantState {
        assert state not in ALLOWED[state] , f"{state.value} -> itself";
    }
}

test "states are stored by their string value" {
    assert [s.value for s in TenantState]
        == [
            "provisioning",
            "configuring",
            "ready_for_go_live",
            "active",
            "suspended",
            "closing",
            "deleted"
        ];
}
