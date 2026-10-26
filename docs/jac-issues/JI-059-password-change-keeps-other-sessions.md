# JI-059: Changing a password leaves every other session signed in

- **Version:** Jac 0.38.0
- **Found:** 2026-10-26, building P12.15 (profile settings).
- **Status:** open; a security gap, not reported upstream (reporting is paused).

## What happens

`update_password(user_id, current, new)` changes the password, but tokens already
issued keep working until they expire. There is no call to revoke a user's tokens
(sign out everywhere), and a token carries nothing the app could compare against a
password change.

## Why it matters

The usual reason to change a password is that someone else may know it. If they're
already signed in, changing it doesn't stop them. A lost phone stays signed in too.

## Workaround

The profile page says plainly that other devices stay signed in and must be signed
out on them. Signing out at the back office already ends the person's shift (ADR-0006),
which limits what a leftover staff token can do. Nothing stops a leftover customer
token.

## Suggested fix

A per-user token version (or "issued after") checked on every request, bumped by
`update_password` and by a `revoke_sessions(user_id)` call.
