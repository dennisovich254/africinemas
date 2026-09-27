# JI-021: `jobj()` returns `None` for a node the caller can't read, but the guides say it resolves regardless of grants

- **Version:** jaclang 0.37.18
- **Found:** 2026-09-27, P1.1 (spike S1: a probe with another tenant's id crashed on `None.__jac__`)
- **Status:** open (docs vs behaviour; the observed behaviour is the safer one)

## Docs
- `jac guide jac-sv-multi-user` (Pitfalls): "`jobj(id)` resolves any node by jid regardless of grants".
- `jac guide jac-sv-persistence`: "**`jobj` resolves regardless of grants** - it never authorizes."

## Behaviour (served app, `JacTestClient`)
Alice creates a `Doc` under her root and grants nothing. Bob calls a `def:priv` endpoint that does `jobj(doc_id)`:
```
owner=WRITE  other=UNRESOLVED     # jobj(doc_id) is None for bob
```
Once alice grants bob access, `jobj` resolves for him.

## Impact
- Code written from the docs (`target = jobj(id); if not can_write(target) {...}`) crashes with `AttributeError: 'NoneType' object has no attribute ...` for a caller without access, instead of reaching its own permission check.
- We haven't checked whether the same holds outside a served context (`jac run`, where there's one root), or for walkers.

## Workaround (in place)
Treat `None` from `jobj` as "not found / not yours", and never rely on `jobj` for authorization in either direction. Resolve client-supplied ids by traversal from the caller's tenant (ADR-0003 rule 3).

## Possible improvement (suggestion)
Update the two guide passages to say that in a served context `jobj` returns `None` when the caller can't read the node. Or, if resolving regardless of grants is the intended contract, restore that behaviour.
