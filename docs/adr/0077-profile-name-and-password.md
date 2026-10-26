# ADR-0077: Your profile: name and password

- **Status:** Accepted
- **Date:** 2026-10-26
- **Sub-phase:** P12.15

## Decision

Everyone who signs in can set their own name and change their own password
(`core/accounts/profile.jac`): staff through **Your profile** in the back office,
which every member sees whatever their role (Settings needs
`tenant.settings.update`), and customers on **My account** at their cinema.

- **The name** is plain text, at most 80 characters, with spaces tidied and no
  `<` or `>`. A customer's name is kept with their storefront account, where sign-up
  already put it. Anyone else's is a claim per account (`profile-name`). Colleagues
  see a staff member's name wherever `staff_name` is used (sales, the door list), in
  place of the name the cinema gave them.
- **The password** is changed through Jac's user manager, so Jac's password rules
  apply and its advice is shown in our words (`password_advice`). The current
  password is asked first. The endpoint only changes the caller's own account: the
  sign-in name a member sends must be one of theirs (`verified_sign_in`), and a
  customer's is worked out from their account, so another account's password can't
  be named.

## Not built, because Jac can't do it yet

- **Changing the sign-in email** (JI-058): an account's email identity can't be
  removed or replaced. The page says the email can't be changed yet.
- **Signing out everywhere** (JI-059): a new password doesn't end other sessions, and
  nothing revokes tokens. The page tells people to sign out on their other devices.
  Ending a shift on sign-out (ADR-0006) still limits a leftover staff token.

Both are built when Jac allows them.

## Consequences

- One more caller-scoped trio in the isolation registry (`my_profile`,
  `save_my_name`, `change_my_password`).
- `my_storefront_account` also returns the customer's name, for My account.
