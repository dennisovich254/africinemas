# JI-020: A grantee revoking their own WRITE grant looks applied, but is silently not persisted

- **Version:** jaclang 0.37.18
- **Found:** 2026-09-27, P1.1 (spike S1: an owner "stepping down" from a tenant kept WRITE access)
- **Status:** open (worked around; may be by design, but the silence is surprising)

## Minimal reproduction (documented APIs only)
```jac
import from uuid { UUID }
import from jaclang { JacRuntime as Jac }
node Doc { has body: str; }

def:priv make_and_share(other_root: str) -> str {        # alice
    d = Doc(body="hello");
    root ++> d;
    Jac.allow_root(d, UUID(other_root), AccessLevel.WRITE);  # jac:ignore[E1053]
    return str(d.__jac__.id);
}
def:priv drop_my_grant(doc_id: str) -> str {             # bob
    d = jobj(doc_id) as Doc;
    Jac.disallow_root(d, UUID(str(root.__jac__.id)));     # jac:ignore[E1053]
    return str(Jac.check_access_level(d.__jac__).name);
}
def:priv level_of(doc_id: str) -> str { ... check_access_level(...) }
```
Driven with `JacTestClient` (alice shares with bob, then bob drops his own grant):
```
before=WRITE  during=NO_ACCESS  after=WRITE
```
Inside bob's request the grant is gone. After the request it's back, and nothing reports an error.

## Why (as far as we can tell from the source)
`Session._flush_locked` (`jaclang/server/impl/session.impl.jac`) re-checks `check_write_access(anchor)` for every dirty anchor under the context's **current** root, and skips anchors that fail with a bare `continue`. By flush time bob no longer holds WRITE, because he just removed it, so the row that removes his grant is skipped.

## Impact
- "Leave a shared doc" or "step down" flows appear to work, then silently don't.
- More generally, any in-request mutation the caller can't write is dropped without an error. That's safe, but a test that only checks in-request values passes while nothing was saved.

## Workaround (in place)
Perform the revocation as the node's owner, and flush the session while still acting as the owner (`core/tenancy/principal.flush_now()`, i.e. `Jac.get_context().mem.flush()`). See ADR-0003 rule 2. We first used `Jac.commit()`, which also works but commits the request's transaction midway (see ADR-0004). Tests assert on persisted state in a follow-up request.

## Possible improvements (suggestions)
- Evaluate the ACL for an access-map change against the permissions held **before** the change, or allow a principal to always remove their own grant.
- Or raise / log a `PermissionDenied` when a dirty anchor is skipped at flush, instead of dropping it silently.
