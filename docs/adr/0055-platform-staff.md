# ADR-0055: AfriCinemas platform staff, apart from every cinema

- **Status:** Accepted; decisions 4, 5 and 8 superseded by ADR-0056 (platform accounts of their own)
- **Date:** 2026-10-22
- **Sub-phase:** P13.1
- **Code:** `core/platform/staff_api.jac`, `core/audit/log.jac` (`platform_audited`, `PLATFORM_COLLECTION`), `web/platform/PlatformConsole.jac`, `web/backoffice/CinemaPicker.jac` (the link to the console)
- **Tests:** `tests/integration/platform_staff_tests.jac`, `tests/isolation/isolation_tests.jac` (the "platform" scope), `e2e/platform_tests.jac`

## Context
Each cinema has its own staff and back office. AfriCinemas needs its own team to review cinemas, suspend fakes and help cinemas with technical problems (Phases 13–15), and that team must never be confused with any cinema's staff or customers.

## Decision
1. **Three roles:** super admin, reviewer and support, each with a fixed set of platform permissions (`PLATFORM_PERMISSIONS`). Endpoints ask for a permission, never a role name.
2. **The founding super admins come from the server's settings** (`AFRICINEMAS_PLATFORM_ADMINS`, read on every request). Nobody can make themselves one through the app, and the app can't change or remove them: they bootstrap a new server, and they're the way back in if the console's staff are removed by mistake or by an attacker. Super admins add reviewers and support staff in the console, kept as permanent claims (`platform-staff`: email → role). A change applies on the member's next request.
3. **Only a settings super admin manages super admins** (owner decision, 2026-10-22). They may make someone a super admin in the console, and only they may change or remove a super admin made there. A stolen session of a console-made super admin can't create more super admins or remove others.
4. **Knowing who's calling.** A request carries only the caller's root, and Jac's identity store doesn't map roots back to people. `platform_whoami` takes the email the browser signed in with, keeps it only if it's the caller's own (`verified_sign_in`), and links the root to it (`platform-member`: root → email). Every platform endpoint finds the caller's role from that link, fresh each time.
5. **Customers can never be platform staff.** Their accounts are usernames with `:` in them (P8.6c), which the staff name check refuses, and they never sign in with an email.
6. **Refusals say nothing about the rules:** outsiders get `not_platform` ("This area is for AfriCinemas staff."), whatever they ask. Platform staff get one `not_allowed` ("Your platform role can't do this.") for anything they may not do, whether it's a missing permission or touching a super admin, so a refusal never reveals which rule applied. Only the settings' super admins see which accounts are the settings' (owner, 2026-10-22: anything more is information an attacker could use). The isolation suite has a "platform" scope and checks that a cinema owner is refused every platform endpoint.
7. **The platform's own audit log:** platform actions are written to one separate collection with the same writer as the cinema audit log. No cinema's log or endpoint reads it. The console's view of it is 13.3.
8. **The console** is `/platform`, behind the staff sign-in, in the back office's shell. It's linked from "Your cinemas" for platform staff only, and it checks the caller on the server; the page is never the guard.

## Consequences
- Signing in to the platform uses the same staff account as a cinema back office: an owner who is also a super admin has one sign-in for both.
- Removing a super admin means editing the server's settings, by design.
- Two-factor sign-in for platform staff is planned with improvements #13 (threat model §3.4).
