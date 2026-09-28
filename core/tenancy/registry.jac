"""The control-plane slug registry (P2.1): which tenant holds which slug.

Backed by atomic claims (core/claims.jac, ADR-0007), not by graph nodes: Jac's graph
find-or-create lets concurrent requests create duplicates (JI-024), while a claim is a
single primary-key insert, so exactly one tenant can hold a slug.

Signup (P2.2) claims provisionally (with a TTL) and makes the claim permanent once the
tenant has committed, so a failed or abandoned signup frees the slug again.
"""

import from core.claims { claim, holder, make_permanent, release }
import from core.tenancy.slugs { normalize_slug, validate_slug }

glob SLUG_NAMESPACE: str = "tenant-slug";

def claim_slug(slug: str, tenant_id: str, ttl_seconds: int = 0) -> str {
    # Records `slug` for `tenant_id` unless another tenant holds it. Returns the holder.
    return claim(SLUG_NAMESPACE, validate_slug(slug), tenant_id, ttl_seconds);
}

def lookup_slug(slug: str) -> str | None {
    return holder(SLUG_NAMESPACE, normalize_slug(slug));
}

def make_slug_permanent(slug: str, tenant_id: str) -> bool {
    return make_permanent(SLUG_NAMESPACE, normalize_slug(slug), tenant_id);
}

def release_slug(slug: str, tenant_id: str) -> bool {
    return release(SLUG_NAMESPACE, normalize_slug(slug), tenant_id);
}
