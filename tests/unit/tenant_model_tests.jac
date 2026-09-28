"""The Tenant node applies the lifecycle rules to its stored state."""

import from core.tenancy.models { Tenant }
import from core.tenancy.state { TenantState, InvalidTransition }

test "a new tenant starts provisioning and moves through allowed states" {
    t = Tenant(slug="nova", name="Nova Cinemas");
    assert t.state == "provisioning";
    for target in [
        TenantState.CONFIGURING,
        TenantState.READY_FOR_GO_LIVE,
        TenantState.ACTIVE,
        TenantState.SUSPENDED
    ] {
        t.move_to(target);
        assert t.state == target.value;
    }
}

test "a refused move leaves the state unchanged" {
    t = Tenant(slug="nova", name="Nova Cinemas");
    t.move_to(TenantState.CONFIGURING);
    refused = False;
    try {
        t.move_to(TenantState.ACTIVE);
    } except InvalidTransition {
        refused = True;
    }
    assert refused , "go-live needs READY_FOR_GO_LIVE first";
    assert t.state == "configuring";
}
