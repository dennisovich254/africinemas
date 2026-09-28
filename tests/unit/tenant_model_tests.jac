"""P2.1: the Tenant node applies the lifecycle rules to its stored state."""

import from core.tenancy.models { Tenant }
import from core.tenancy.state { TenantState, InvalidTransition }

test "a new tenant starts provisioning and moves through allowed states" {
    t = Tenant(slug="nova", name="Nova Cinemas");
    assert t.state == "provisioning";
    t.move_to(TenantState.ACTIVE);
    assert t.state == "active";
    t.move_to(TenantState.SUSPENDED);
    assert t.state == "suspended";
}

test "a refused move leaves the state unchanged" {
    t = Tenant(slug="nova", name="Nova Cinemas");
    t.move_to(TenantState.ACTIVE);
    t.move_to(TenantState.CLOSED);
    try {
        t.move_to(TenantState.ACTIVE);
        assert False , "closed is final";
    } except InvalidTransition {}
    assert t.state == "closed";
}
