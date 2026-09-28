"""Tenant lifecycle.

PROVISIONING -> ACTIVE (signup finished) or CLOSED (signup abandoned).
ACTIVE <-> SUSPENDED (billing or abuse). ACTIVE or SUSPENDED -> CLOSED, which is final.
Values are stored as strings on the Tenant node.
"""

enum TenantState {
    PROVISIONING = "provisioning",
    ACTIVE = "active",
    SUSPENDED = "suspended",
    CLOSED = "closed"
}

glob ALLOWED: dict[TenantState, set[TenantState]] = {
         TenantState.PROVISIONING: {TenantState.ACTIVE, TenantState.CLOSED},
         TenantState.ACTIVE: {TenantState.SUSPENDED, TenantState.CLOSED},
         TenantState.SUSPENDED: {TenantState.ACTIVE, TenantState.CLOSED},
         TenantState.CLOSED: set()
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
