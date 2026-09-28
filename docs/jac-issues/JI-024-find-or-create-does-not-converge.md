# JI-024: Concurrent find-or-create does not converge: racing requests each create their own node

- **Version:** jaclang 0.37.18, `jac run` with the embedded Postgres
- **Found:** 2026-09-28, P2.1 (the unique-slug test: eight concurrent claims of one slug)
- **Status:** open. **High**: tenant slugs, and later seat holds (P4), rely on this guarantee.

## Docs
`jac guide reference/persistence`, "Concurrent writes: check-then-create and convergence":
> "Two racing find-or-creates converge on one node; the client sees a normal `200`, not a duplicate and not an error."
> "When two requests race on overlapping data, Postgres lets one commit and aborts the other with a serialization conflict before it can write a duplicate."

## Minimal reproduction (documented pattern only, no internals)
```jac
node Item { has key: str; }

def:pub ensure(wanted: str) -> int {
    if not [root-->[?:Item, key == wanted]] {
        root ++> Item(key=wanted);
    }
    return len([root-->[?:Item, key == wanted]]);
}

def:pub count(wanted: str) -> int {
    return len([root-->[?:Item, key == wanted]]);
}
```
The app is served with `jac run` (a `service` app). For each of 3 keys, 8 threads call `ensure` at once. Afterwards, `count` is called once per key.

| Variant | Items per key after the race (expected 1, 1, 1) |
| --- | --- |
| anonymous, defaults | 4, 1, 8 |
| anonymous, `JAC_DB_RO_UNITS=0` | 7, 8, 4 |
| signed-in user (all requests on one root), defaults | 1, 1, 2 · 3, 1, 2 · 4, 2, 1 |
| signed-in user, `JAC_DB_RO_UNITS=0` | 1, 1, 1 · 2, 1, 1 · 1, 1, 2 |

Every response was `200`, so no error signals the duplicates. In the app's own registry flow (the same shape, while acting as the system root), one racer instead got a `500` carrying the raw Postgres error `40001 could not serialize access due to read/write dependencies among transactions … during read`. The docs describe a replay, not an error.

## What we can say
- Duplicates appear in every variant, including with the read tier turned off. That tier (the default `JAC_DB_RO_UNITS`) makes them more frequent.
- We haven't identified the mechanism. A guess, unverified: the root's edge list is served from memory rather than read from the database, so Postgres never sees the read that SERIALIZABLE needs to detect the conflict.
- Only the embedded Postgres under `jac run` was tested, not an external database.

## Impact
- Any "check, then create" uniqueness (tenant slugs, one customer profile per tenant, **one hold per seat**) can be broken by concurrent requests.
- Sometimes a raw `40001` escapes as a `500` instead of being replayed.

## Workaround
Pending a decision (see P2.1). Candidates:
1. An atomic database-level claim, as Jac's own token store does: `INSERT … ON CONFLICT DO NOTHING` in the shared store.
2. Deterministic node ids, so racers collide on the same key.
3. Serialising the critical section.

## Possible improvement (suggestion)
Make the documented convergence hold: take the read locks SERIALIZABLE needs, and map `40001` raised during a read to the replay path. Or document the limits, and offer a unique-key primitive for nodes.
