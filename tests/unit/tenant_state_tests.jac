"""P2.1: tenant lifecycle states and the transitions between them.

PROVISIONING -> ACTIVE (signup finished) or CLOSED (signup abandoned);
ACTIVE <-> SUSPENDED (billing, abuse); ACTIVE or SUSPENDED -> CLOSED. CLOSED is final.
"""

import from core.tenancy.state { TenantState, InvalidTransition, ALLOWED, transition }


test "allowed transitions return the new state" {
    for (current, target) in [
        (TenantState.PROVISIONING, TenantState.ACTIVE),
        (TenantState.PROVISIONING, TenantState.CLOSED),
        (TenantState.ACTIVE, TenantState.SUSPENDED),
        (TenantState.SUSPENDED, TenantState.ACTIVE),
        (TenantState.ACTIVE, TenantState.CLOSED),
        (TenantState.SUSPENDED, TenantState.CLOSED)
    ] {
        assert transition(current, target) == target , f"{current} -> {target}";
    }
}

test "every other transition is refused" {
    for current in TenantState {
        for target in TenantState {
            if target not in ALLOWED[current] {
                try {
                    transition(current, target);
                    assert False , f"{current} -> {target} should be refused";
                } except InvalidTransition {}
            }
        }
    }
}

test "closed is final and staying put is not a transition" {
    assert ALLOWED[TenantState.CLOSED] == set();
    for state in TenantState {
        assert state not in ALLOWED[state] , f"{state} -> itself";
    }
}

test "states are stored by their string value" {
    assert [s.value for s in TenantState]
        == ["provisioning", "active", "suspended", "closed"];
    assert TenantState("active") == TenantState.ACTIVE;
}
