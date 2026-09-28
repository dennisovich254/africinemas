"""Tenant lifecycle (architecture §92-§94).

PROVISIONING   exists only inside the signup transaction (P2.2): it commits as CONFIGURING.
CONFIGURING    onboarding checklist in progress (§134).
READY_FOR_GO_LIVE  checklist complete; the go-live gate (§135) moves it to ACTIVE.
ACTIVE <-> SUSPENDED (billing, abuse; §93).
CLOSING        cooling-off before deletion (§94); cancellable back to ACTIVE/CONFIGURING.
DELETED        final.
Values are stored as strings on the Tenant node.
"""

enum TenantState {
    PROVISIONING = "provisioning",
    CONFIGURING = "configuring",
    READY_FOR_GO_LIVE = "ready_for_go_live",
    ACTIVE = "active",
    SUSPENDED = "suspended",
    CLOSING = "closing",
    DELETED = "deleted"
}

glob ALLOWED: dict[TenantState, set[TenantState]] = {
         TenantState.PROVISIONING: {TenantState.CONFIGURING},
         TenantState.CONFIGURING: {TenantState.READY_FOR_GO_LIVE, TenantState.CLOSING},
         TenantState.READY_FOR_GO_LIVE: {TenantState.ACTIVE, TenantState.CONFIGURING},
         TenantState.ACTIVE: {TenantState.SUSPENDED, TenantState.CLOSING},
         TenantState.SUSPENDED: {TenantState.ACTIVE, TenantState.CLOSING},
         TenantState.CLOSING: {
             TenantState.DELETED,
             TenantState.ACTIVE,
             TenantState.CONFIGURING
         },
         TenantState.DELETED: set()
     };

class InvalidTransition(ValueError) {}

def transition(current: TenantState, target: TenantState) -> TenantState {
    if target not in ALLOWED[current] {
        raise InvalidTransition(
            f"a tenant can't go from {current.value} to {target.value}"
        );
    }
    return target;
}
