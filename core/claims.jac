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

import json;
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

def take_claim(namespace: str, key: str) -> str | None {
    # Removes a live claim and returns its value, in one statement: exactly one caller
    # gets it, and never once it has expired. For single-use secrets (P8.6a).
    taken = _store().rows(
        """
        DELETE FROM kv_state
        WHERE key = :k AND (expires_at IS NULL OR expires_at > now())
        RETURNING value
        """,
        {"k": _key(namespace, key)}
    );
    return str(taken[0][0]) if taken else None;
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

# Stock counters (P12.4, ADR-0041): per key, a JSON value {"on_hand": n, "reserved": n},
# changed only by single statements, so concurrent sales and adjustments can't
# oversell or lose a change. Each returns the counts after the change, or None when the
# change would break its guard (nothing changes then).

def _counts(found: list[any]) -> tuple[int, int] | None {  # jac:ignore[W1037]
    if not found {
        return None;
    }
    value: dict[str, any] = json.loads(str(found[0][0]));  # jac:ignore[W1037]
    return (int(value.get("on_hand", 0)), int(value.get("reserved", 0)));
}

def stock_counts(namespace: str, key: str) -> tuple[int, int] {
    # (on hand, reserved); (0, 0) for a key never stocked.
    found = _counts(
        _store().rows(
            "SELECT value FROM kv_state WHERE key = :k", {"k": _key(namespace, key)}
        )
    );
    return found if found is not None else (0, 0);
}

def stock_change(namespace: str, key: str, delta: int) -> tuple[int, int] | None {
    # Adds `delta` to on hand, unless that would go below zero. Adding creates the
    # counts on first use; taking away needs counts to take from.
    k = _key(namespace, key);
    if delta >= 0 {
        return _counts(
            _store().rows(
                """
                INSERT INTO kv_state (key, value, expires_at)
                VALUES (:k, json_build_object('on_hand', CAST(:d AS int), 'reserved', 0)::text, NULL)
                ON CONFLICT (key) DO UPDATE
                    SET value = jsonb_set(
                            kv_state.value::jsonb, '{on_hand}',
                            to_jsonb((kv_state.value::jsonb->>'on_hand')::int + CAST(:d AS int))
                        )::text,
                        updated_at = now()
                RETURNING value
                """,
                {"k": k, "d": delta}
            )
        );
    }
    return _counts(
        _store().rows(
            """
            UPDATE kv_state
            SET value = jsonb_set(
                    value::jsonb, '{on_hand}',
                    to_jsonb((value::jsonb->>'on_hand')::int + CAST(:d AS int))
                )::text,
                updated_at = now()
            WHERE key = :k AND (value::jsonb->>'on_hand')::int + CAST(:d AS int) >= 0
            RETURNING value
            """,
            {"k": k, "d": delta}
        )
    );
}

def stock_reserve(namespace: str, key: str, quantity: int) -> tuple[int, int] | None {
    # Reserves `quantity` if that many are available (on hand − reserved).
    return _counts(
        _store().rows(
            """
            UPDATE kv_state
            SET value = jsonb_set(
                    value::jsonb, '{reserved}',
                    to_jsonb((value::jsonb->>'reserved')::int + CAST(:q AS int))
                )::text,
                updated_at = now()
            WHERE key = :k
              AND (value::jsonb->>'on_hand')::int - (value::jsonb->>'reserved')::int >= CAST(:q AS int)
            RETURNING value
            """,
            {"k": _key(namespace, key), "q": quantity}
        )
    );
}

def stock_release(namespace: str, key: str, quantity: int) -> tuple[int, int] | None {
    # Gives back up to `quantity` reserved (an order that ended unpaid).
    return _counts(
        _store().rows(
            """
            UPDATE kv_state
            SET value = jsonb_set(
                    value::jsonb, '{reserved}',
                    to_jsonb(GREATEST((value::jsonb->>'reserved')::int - CAST(:q AS int), 0))
                )::text,
                updated_at = now()
            WHERE key = :k
            RETURNING value
            """,
            {"k": _key(namespace, key), "q": quantity}
        )
    );
}

def stock_commit(namespace: str, key: str, quantity: int) -> tuple[int, int] | None {
    # A reserved sale went through: `quantity` leaves on hand and reserved together.
    return _counts(
        _store().rows(
            """
            UPDATE kv_state
            SET value = jsonb_build_object(
                    'on_hand', (value::jsonb->>'on_hand')::int - CAST(:q AS int),
                    'reserved', GREATEST((value::jsonb->>'reserved')::int - CAST(:q AS int), 0)
                )::text,
                updated_at = now()
            WHERE key = :k AND (value::jsonb->>'on_hand')::int >= CAST(:q AS int)
            RETURNING value
            """,
            {"k": _key(namespace, key), "q": quantity}
        )
    );
}
