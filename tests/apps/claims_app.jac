"""Test-only app entry exposing core.claims (ADR-0007). Never imported by main.jac."""

import from core.claims { claim, holder, make_permanent, release }

# `ttl` has no default on purpose: omitted non-string defaults arrive as strings (JI-025).
def:pub c_claim(ns: str, key: str, owner: str, ttl: int) -> str {
    return claim(ns, key, owner, ttl);
}

def:pub c_holder(ns: str, key: str) -> str | None {
    return holder(ns, key);
}

def:pub c_permanent(ns: str, key: str, owner: str) -> bool {
    return make_permanent(ns, key, owner);
}

def:pub c_release(ns: str, key: str, owner: str) -> bool {
    return release(ns, key, owner);
}
