"""Tenancy archetypes (P2.1).

Ownership follows the Phase 1 ADRs:
- A Tenant, its StaffGroups and everything under them are owned by the tenant's
  service principal (ADR-0003); staff reach them through group grants (ADR-0004).
- Which tenant holds which slug is not a graph node: it is an atomic claim
  (core/tenancy/registry.jac, ADR-0007), because graph find-or-create can duplicate
  under concurrency (JI-024).
"""

import from core.tenancy.state { TenantState, transition }

node Tenant {
    has slug: str,
        name: str,
        state: str = TenantState.PROVISIONING.value,
        principal_root_id: str = "",
        created_at: str = "";

    def move_to(target: TenantState) {
        self.state = transition(TenantState(self.state), target).value;
    }
}

node StaffGroup {
    # One group per role within a tenant (roles: P2.3).
    has tenant_id: str,
        role: str;
}

node CustomerProfile {
    # A person's customer record at one tenant; the same person at another tenant
    # gets a separate profile (P2.6).
    has tenant_id: str,
        display_name: str = "";
}

edge MemberOf {}

edge ForTenant {}
