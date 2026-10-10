# JI-044: The same root id comes in two forms: hex from the identity store, dashed from node_id

- **Version:** jaclang 0.37.18
- **Found:** 2026-10-10, P8.6a (signing Claude in with OAuth)
- **Status:** open (we normalise with `uuid.UUID(x)` before storing or comparing)

## What we saw (in-process app, `tests/integration/oauth_tests.jac`)
`UserManager.create_user(...)` returns the new account's `root_id` as 32 hex characters (`23e7d1a5388b44a8b35badb59a00bcf1`). A request signed in as that account sees `node_id(root)` as a dashed UUID (`23e7d1a5-388b-44a8-b35b-adb59a00bcf1`). Our link from chat account to customer was keyed by one form and looked up by the other, so it never matched. The token itself was accepted: the request ran as the right account.

The isolation tests had met the same thing earlier (`_norm` in `tests/isolation/isolation_tests.jac`, comparing `register_actor`'s root id with ids in answers).

## Workaround (in place)
`core/oauth/state.jac` keys every root id by `same_id(x)` (`str(uuid.UUID(x))`), on the way in and on the way out.

## Suggestion upstream
Return one canonical form everywhere (`str(UUID)`), or document that `root_id` from the identity store is `UUID.hex`.
