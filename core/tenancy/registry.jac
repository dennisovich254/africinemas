"""The control-plane slug registry (P2.1): which tenant holds which slug.

Backed by atomic claims (core/claims.jac, ADR-0007), not by graph nodes: Jac's graph
find-or-create lets concurrent requests create duplicates (JI-024), while a claim is a
single primary-key insert, so exactly one tenant can hold a slug.

P2.1 claims are permanent. Signup (P2.2) will claim provisionally (with a TTL) and make
the claim permanent once the tenant has been created, so an abandoned signup frees the
slug again.
"""

import from core.claims { claim, holder }
import from core.tenancy.slugs { normalize_slug, validate_slug }

glob SLUG_NAMESPACE: str = "tenant-slug";

def claim_slug(slug: str, tenant_id: str, ttl_seconds: int = 0) -> str {
    # Records `slug` for `tenant_id` unless another tenant holds it. Returns the holder.
    return claim(SLUG_NAMESPACE, validate_slug(slug), tenant_id, ttl_seconds);
}

def lookup_slug(slug: str) -> str | None {
    return holder(SLUG_NAMESPACE, normalize_slug(slug));
}
