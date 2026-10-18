"""Test-only app entry exposing the tenant slug registry (P2.1). Never imported by main.jac.

Public on purpose so tests can fire truly concurrent anonymous requests at a real
server; the production signup flow (P2.2) wraps the registry behind authentication.
"""

import from core.tenancy.slugs { InvalidSlug }
import from core.tenancy.registry { claim_slug, lookup_slug }

def:pub t_claim(slug: str, tenant_id: str) -> dict[str, str] {
    try {
        return {"owner": claim_slug(slug, tenant_id)};
    } except InvalidSlug as e {
        return {"error": e.reason};
    }
}

def:pub t_lookup(slug: str) -> str | None {
    return lookup_slug(slug);
}
