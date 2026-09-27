# JI-022: The guide's invitation-token example consumes the token in the function body, which the persistence reference says is not replay-safe

- **Version:** jaclang 0.37.18
- **Found:** 2026-09-27, P1.2 (spike S2: the first invite redeemed in a fresh app came back "not joined")
- **Status:** open (docs; worked around)

## Docs
- `jac guide jac-sv-multi-user`, "Invitation tokens: app_tokens":
  ```jac
  def accept(token: str) -> dict[str, any] {
      got = token_consume("org-invite", token);   # exactly one caller wins
      if got is None { return {"ok": False}; }
      ...
  ```
- `jac guide reference/persistence`, "Side effects and replay": a request can be replayed from the start (on a write conflict, and on the first write of a unit the process has only seen reading). So an external side effect in the body, and it names "registering a token", should be deferred with `on_commit`.

The token store writes outside the graph transaction: `AuthTokenStore` deletes the token with its own statement on the shared store. A consume in the body is therefore not rolled back when the request is replayed, and the replay finds the token gone.

## What we observed
Our first join flow followed the example (`token_consume` in the body). Its first call in a fresh app ran **twice** (an append-only log outside the transaction showed two executions): attempt 1 consumed the token, and attempt 2 got `None`, so the invite was burned and the user was told it was invalid.

We can't say which replay trigger fired. That version also called `Jac.commit()` mid-request, which may have provoked a conflict. So this is a docs mismatch backed by the documented semantics, not a proven runtime bug.

## Workaround (in place)
`token_peek` in the body, enforce single use with a node inside the transaction (`Invite.used_by`), and `on_commit(lambda { token_consume(...); })`. See ADR-0004.

## Possible improvement (suggestion)
Show the accept example with `token_peek` plus `on_commit(token_consume)` and a graph-side used marker. Or make `token_consume` join the request's transaction so it rolls back on replay.
