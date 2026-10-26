# JI-058: An account's sign-in email can't be changed

- **Version:** Jac 0.38.0
- **Found:** 2026-10-26, building P12.15 (profile settings).
- **Status:** open; a feature gap, not reported upstream (reporting is paused).

## What we needed

A member of staff who changes their email (a new job address, a typo at sign-up)
should be able to sign in with the new one, after confirming it, and no longer with
the old one.

## What Jac offers

The user manager (`Jac.get_user_manager(...)`) has `find_user_by_identity`,
`add_identity`, `rename_username`, `update_password` and `update_user_fields`. There
is no call that removes or replaces an identity. An account holds one `email`
identity, so `add_identity` with a second email is refused, and the old email can't
be taken away. `rename_username` only covers `username` identities, and staff sign
in with an `email` identity.

## Workaround

None that is safe. Making a new account and moving the old one's memberships would
lose its root (everything the person owns in the graph). The profile page says the
email can't be changed yet.

## Suggested fix

A `replace_identity(user_id, old, new)` (or `remove_identity`) on the user manager,
so an app can confirm the new address first and then swap it in one step.
