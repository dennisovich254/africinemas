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
     ACCESS_GROUP: str = "staff",
     NAME_MAX: int = 80;

node Tenant {
    has slug: str,
        name: str,
        state: str = TenantState.PROVISIONING.value,
        principal_root_id: str = "",
        created_at: str = "",
        # The cinema's public Storefront on root.shared (P3.5b), made on first publish.
        # The only trusted way to reach it: anyone may attach nodes to root.shared.
        storefront_id: str = "",
        # The cinema's PriceList (P3.6), made on its first save. Setting it makes two
        # concurrent first saves write the same record, so only one list is created.
        price_list_id: str = "";

    def move_to(target: TenantState) {
        self.state = transition(TenantState(self.state), target).value;
    }
}

node StaffGroup {
    # The tenant's access group: tenant nodes grant it WRITE, one entry per node
    # (ADR-0004). Every staff member has a MemberOf edge to it; roles are not here.
    has tenant_id: str,
        role: str = ACCESS_GROUP;
}

node Membership {
    # The tenant's record of one staff member (ADR-0008, P2.5), owned by the tenant's
    # principal and readable only by that member: their MemberOf edge (so the tenant can
    # remove it), their role keys ("usher", "usher@venue-1") and their status.
    has staff_root_id: str,
        edge_id: str,
        roles: list[str] = [],
        status: str = "active",
        joined_at: str = "";
}

node Invite {
    # A pending staff invitation, owned by the tenant's principal. Single use is decided
    # by an atomic claim on its id (ADR-0007); `used_by` records who accepted.
    has role_key: str,
        invited_by: str,
        created_at: str,
        used_by: str = "";
}

node CustomerProfile {
    # A person's customer record at ONE cinema (P2.6): owned by the cinema's principal,
    # readable by that customer only; the same person at another cinema has another one.
    # One per (cinema, person) is guaranteed by an atomic claim (ADR-0007).
    has tenant_id: str,
        customer_root_id: str,
        display_name: str,
        created_at: str;
}

edge MemberOf {}

edge ForTenant {}
