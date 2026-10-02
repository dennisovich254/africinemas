"""Atomic unique claims (ADR-0007): one owner per (namespace, key), even under concurrency.

Jac's graph find-or-create does not reliably converge under concurrent requests
(docs/jac-issues/JI-024), so uniqueness is enforced where the database can guarantee
it: a primary key. Each claim is a single statement on Jac's shared store table
`kv_state` (the table Jac's own token store uses):

    INSERT ... ON CONFLICT (key) DO UPDATE ... WHERE the existing claim has expired

Exactly one caller wins; everyone else is told the holder. Claims run on the shared
store's own connection and commit at once, outside the request's graph transaction.
So a claim made by a request that later fails stays behind: give provisional claims
a TTL and make them permanent (or release them) once the work has committed.

The only module allowed to use the shared store; contract tests: tests/integration/
claims_tests.jac and tenant_slug_concurrency_tests.jac.
"""

import from jaclang.server.shared_store { shared_store }

glob PREFIX: str = "africinemas:claim:";

class ClaimStoreUnavailable(RuntimeError) {}

def _store -> any {  # jac:ignore[W1037]
    store = shared_store();
    if store is None {
        raise ClaimStoreUnavailable("the shared store is not reachable");
    }
    return store;
}

def _key(namespace: str, key: str) -> str {
    return f"{PREFIX}{namespace}:{key}";
}

def claim(namespace: str, key: str, owner: str, ttl_seconds: int = 0) -> str {
    # Claims `key` for `owner` unless someone else holds it (an expired claim is taken
    # over). Returns the holder afterwards. `ttl_seconds` 0 means permanent.
    k = _key(namespace, key);
    if ttl_seconds > 0 {
        taken = _store().rows(
            """
            INSERT INTO kv_state (key, value, expires_at)
            VALUES (:k, :v, now() + make_interval(secs => CAST(:ttl AS float8)))
            ON CONFLICT (key) DO UPDATE
                SET value = EXCLUDED.value, expires_at = EXCLUDED.expires_at, updated_at = now()
                WHERE kv_state.expires_at IS NOT NULL AND kv_state.expires_at <= now()
            RETURNING value
            """,
            {"k": k, "v": owner, "ttl": ttl_seconds}
        );
    } else {
        taken = _store().rows(
            """
            INSERT INTO kv_state (key, value, expires_at)
            VALUES (:k, :v, NULL)
            ON CONFLICT (key) DO UPDATE
                SET value = EXCLUDED.value, expires_at = NULL, updated_at = now()
                WHERE kv_state.expires_at IS NOT NULL AND kv_state.expires_at <= now()
            RETURNING value
            """,
            {"k": k, "v": owner}
        );
    }
    if taken {
        return str(taken[0][0]);
    }
    held = holder(namespace, key);
    return held if held is not None else owner;
}

def holder(namespace: str, key: str) -> str | None {
    return _store().kv_get(_key(namespace, key));
}

def make_permanent(namespace: str, key: str, owner: str) -> bool {
    # Turns `owner`'s live provisional claim into a permanent one.
    return bool(
        _store().rows(
            """
            UPDATE kv_state SET expires_at = NULL, updated_at = now()
            WHERE key = :k AND value = :v AND (expires_at IS NULL OR expires_at > now())
            RETURNING key
            """,
            {"k": _key(namespace, key), "v": owner}
        )
    );
}

def release(namespace: str, key: str, owner: str) -> bool {
    # Only the holder can release a claim.
    return bool(
        _store().rows(
            "DELETE FROM kv_state WHERE key = :k AND value = :v RETURNING key",
            {"k": _key(namespace, key), "v": owner}
        )
    );
}

def renew(namespace: str, key: str, owner: str, ttl_seconds: int) -> bool {
    # Extends `owner`'s live claim to `ttl_seconds` from now (0: permanent). False when
    # `owner` doesn't hold a live claim.
    if ttl_seconds > 0 {
        sql = """
            UPDATE kv_state
            SET expires_at = now() + make_interval(secs => CAST(:ttl AS float8)), updated_at = now()
            WHERE key = :k AND value = :v AND (expires_at IS NULL OR expires_at > now())
            RETURNING key
            """;
        return bool(
            _store().rows(
                sql, {"k": _key(namespace, key), "v": owner, "ttl": ttl_seconds}
            )
        );
    }
    return make_permanent(namespace, key, owner);
}

def claims_in(namespace: str) -> list[tuple[str, str, float]] {
    # Every claim in `namespace`, live or lapsed, as (key, owner, seconds since it was
    # made or last changed), oldest first.
    prefix = _key(namespace, "");
    found = _store().rows(
        """
        SELECT key, value, EXTRACT(EPOCH FROM now() - updated_at) FROM kv_state
        WHERE left(key, :n) = :p
        ORDER BY updated_at
        """,
        {"n": len(prefix), "p": prefix}
    );
    return [(str(r[0])[len(prefix):], str(r[1]), float(r[2])) for r in found];
}

def drop_lapsed(namespace: str) -> int {
    # Deletes the lapsed claims in `namespace` and in every namespace under it ("seat"
    # covers "seat:<showtime>"): they hold nothing, but each leaves a row. A claim taken
    # over at the same moment has a new expiry, so the delete passes it by. Returns how
    # many were deleted.
    prefix = f"{PREFIX}{namespace}:";
    return len(
        _store().rows(
            """
            DELETE FROM kv_state
            WHERE left(key, :n) = :p AND expires_at IS NOT NULL AND expires_at <= now()
            RETURNING key
            """,
            {"n": len(prefix), "p": prefix}
        )
    );
}
