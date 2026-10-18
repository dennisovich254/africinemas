"""Test-only app entry exposing core.claims (ADR-0007). Never imported by main.jac."""

import from core.claims { claim, holder, make_permanent, release, take_claim }

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

def:pub c_take(ns: str, key: str) -> str | None {
    return take_claim(ns, key);
}

# Stock counters (P12.4).
import from core.claims {
    stock_counts,
    stock_change,
    stock_reserve,
    stock_release,
    stock_commit
}

def:pub c_stock(key: str) -> list[int] {
    return list(stock_counts("stock", key));
}

def:pub c_stock_change(key: str, delta: int) -> list[int] | None {
    got = stock_change("stock", key, delta);
    return list(got) if got is not None else None;
}

def:pub c_stock_reserve(key: str, quantity: int) -> list[int] | None {
    got = stock_reserve("stock", key, quantity);
    return list(got) if got is not None else None;
}

def:pub c_stock_release(key: str, quantity: int) -> list[int] | None {
    got = stock_release("stock", key, quantity);
    return list(got) if got is not None else None;
}

def:pub c_stock_commit(key: str, quantity: int) -> list[int] | None {
    got = stock_commit("stock", key, quantity);
    return list(got) if got is not None else None;
}
