"""Tenancy archetypes (P2.1).

Ownership follows the Phase 1 ADRs:
- A Tenant, its StaffGroups and everything under them are owned by the tenant's
  service principal (ADR-0003); staff reach them through group grants (ADR-0004).
- Which tenant holds which slug is not a graph node: it is an atomic claim
  (core/tenancy/registry.jac, ADR-0007), because graph find-or-create can duplicate
  under concurrency (JI-024).
"""

import from core.tenancy.state { TenantState, transition }

glob ROLE_OWNER: str = "owner",
     # The one group per tenant that holds the graph grants on its nodes (ADR-0004).
     # Every staff member belongs to it; it grants no role (ADR-0008).
     ACCESS_GROUP: str = "staff",
     NAME_MAX: int = 80;

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
    # Either the tenant's access group (role ACCESS_GROUP: holds the node grants) or a
    # role group (a policy role, optionally at one venue: no node grants).
    has tenant_id: str,
        role: str,
        venue_id: str = "";
}

node Membership {
    # The tenant's own record of a staff membership (ADR-0004): which root joined, and
    # the id of their MemberOf edge, so the tenant can find and remove it later.
    has staff_root_id: str,
        edge_id: str,
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
