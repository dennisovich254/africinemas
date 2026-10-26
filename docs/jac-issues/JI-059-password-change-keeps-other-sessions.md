# JI-059: Changing a password leaves every other session signed in

- **Version:** Jac 0.38.0
- **Found:** 2026-10-26, building P12.15 (profile settings).
- **Status:** open; a security gap, not reported upstream (reporting is paused).

## What happens

`update_password(user_id, current, new)` changes the password, but tokens already
issued keep working until they expire (7 days by default, `token_ttl_days`).

Checked in Jac's own source (`jaclang/server/identity`), 2026-10-26:

- **Jac issues the token** (`create_jwt_token`): it carries `sub`, `iat` (when it was
  issued) and `exp`, signed with the project's secret.
- **Jac checks it** (`validate_jwt_token_detail`): the signature and `exp`, nothing
  else, before the endpoint runs. The endpoint gets the account's root, never the
  token, so the app can't read `iat` or tell one session from another.
- **Jac refreshes it** (`/user/refresh-token`, `refresh_jwt_token`): any valid token
  gets a new one with a fresh `iat`, without the app being asked. A stolen token can
  renew itself indefinitely.
- `revoke_user_tokens` exists, but only for one-off tokens with a purpose (password
  reset links), not sign-in tokens.

So the usual fix, a per-account cut-off that refuses tokens issued before it, needs a
hook in Jac's check and in its refresh, and the app has neither.

## Why it matters

The usual reason to change a password is that someone else may know it. If they're
already signed in, changing it doesn't stop them. A lost phone stays signed in too.

## Workaround

For now, the profile page says plainly that other devices stay signed in and must be
signed out on them. Signing out at the back office already ends the person's shift
(ADR-0006), and an owner can disable a member at once on the Staff page (membership is
checked on every request). Nothing stops a leftover customer token.

If Jac hasn't fixed it by P17.5, we build our own: a session code made right after
Jac's sign-in, kept as a claim under the account, sent with every request and checked
before every endpoint. A password change, Sign out everywhere, or disabling a member
deletes the account's codes. It's real work (every endpoint, and the isolation
registry checks none is missed), but it doesn't depend on Jac.

## Suggested fix

A per-account "valid from" (or token version) checked in `validate_jwt_token_detail`
and in `refresh_jwt_token`, moved forward by `update_password` and by a
`revoke_sessions(user_id)` call.
