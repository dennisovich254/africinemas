# ADR-0056: Platform accounts of their own, by invitation only

- **Status:** Accepted
- **Date:** 2026-10-23
- **Sub-phase:** P13.1b.a
- **Supersedes:** ADR-0055 decisions 4, 5 and 8, and its first consequence
- **Code:** `core/platform/accounts.jac`, `core/platform/staff_api.jac` (`invite_platform_member`, `platform_join`), `core/platform/setup_file.jac`, `scripts/platform_setup.sh` and `.jac`, `web/platform/PlatformAuthPages.jac`, `web/platform/platform_session.jac`, `web/auth/token_slots.jac` (the platform slot), `core/tenancy/signup.jac` and `core/tenancy/staff_api.jac` (platform accounts kept out of the back office)
- **Tests:** `tests/integration/platform_staff_tests.jac`, `tests/isolation/registry.jac`, `e2e/platform_tests.jac`

## Context
Under ADR-0055 platform staff signed in with their cinema staff account, and the console learned their email from what the browser remembered. A customer sign-in in the same browser erased that, and the owner was locked out of the console (fixed in #140). The owner wants the platform, the back office and the storefronts to behave as three separate websites (plan 13.1b), and the platform never to offer a sign-up page: only invitations from a super admin (owner decisions, 2026-10-23).

## Decision
1. **A platform account is its own account.** Its username is `platform:<local part>:<domain>`. `platform` is a reserved slug, so the name can never be a cinema's customer account. It has its own password, apart from any cinema account with the same email. A permanent claim `platform-account` on its root names its email, and every platform endpoint reads the caller's email from that claim, never from the browser.
2. **Only the server makes one, from a join link.** A join link is a single-use token naming an email. A super admin's invitation is valid for 72 hours. For the super admins in the server's settings, `scripts/platform_setup.sh` prints a link valid for 24 hours. It's the only way their account is made, or a forgotten password replaced, and only someone who can run commands on the server sees it. The page `/platform/join#<token>` keeps the token in the address fragment, which browsers never send to the server. A new link for an email cancels the last one.
3. **No sign-up.** There's no sign-up page or endpoint for the platform. A `platform:` name made through Jac's own `/user/register` has no claim, so it's no one's platform account. Joining deletes it and makes the account afresh, so a squatter already signed in to it never gets the role.
4. **Invitations go through Platform staff.** Inviting adds the email with its role at once, shown as "Invited" until they set their password. Removing someone before they join cancels the link. Someone who has joined can't be invited again, because the link sets the password and would take over their account. Joining is refused once the email no longer has a role. The password is checked before the link is spent, so a weak one can be tried again.
5. **The platform's own sign-in.** `/platform/sign-in` and the console keep their token in a slot of their own (`africinemas_token:platform`), so signing in or out of the platform never touches a cinema's back office or storefront in the same browser, nor the reverse. Signed-out visitors to `/platform` go to the platform's sign-in, not the staff one. "Your cinemas" no longer links to the console.
6. **Platform accounts stay on the platform.** Creating a cinema and accepting a cinema staff invitation refuse a platform account (`platform_account`), as they refuse customer accounts.
7. **The browser tests' join link.** Their server has its own database, which the setup script can't reach. When `AFRICINEMAS_PLATFORM_SETUP_FILE` is set (`scripts/e2e_env.sh` only), a job writes the settings' super admins' links to that file once, like the email outbox. Unset, it does nothing.

## Consequences
- An owner who is also a super admin has two sign-ins: one for their cinemas and one for the platform. That's the intent.
- Invitations aren't emailed yet: the super admin copies the link and sends it themselves. Emailing them can follow once outgoing mail is configured in production.
- 13.1b.b moves the console to its own address (`admin.<domain>`). The slot then matters less, since browsers keep each address's storage apart.
