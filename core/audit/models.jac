"""The audit log's nodes (P7.2, architecture §66, §67; ADR-0027).

Tenant -> AuditTrail -> AuditEvent, owned by the cinema's principal. Unlike every other
tenant node, an event is granted to the cinema's access group READ, not WRITE: staff,
owners included, can see it but not change or delete it, and no endpoint does either.
"""

node AuditTrail {
    # The cinema's one trail, made with its first event.
    has tenant_id: str;
}

node AuditEvent {
    # One staff action at the cinema. at is UTC ISO 8601; actor_id is the member's root
    # id and actor how they were known then (their email, or the invitation's label).
    # result is "ok" or the refusal's code ("forbidden", "not_found", "no_shift", ...).
    # detail is a short note with no secrets (e.g. the roles given).
    has tenant_id: str,
        at: str,
        actor_id: str,
        actor: str,
        action: str,
        resource_type: str,
        resource_id: str,
        result: str,
        detail: str = "",
        correlation_id: str = "";
}
