# ADR-0071: Reviewing a cinema's verification in the platform console

- **Status:** Accepted
- **Date:** 2026-10-24
- **Sub-phase:** P14.5a
- **Code:** `core/platform/review_api.jac`, `core/tenancy/verification.jac` (`decide`, `verified_at`), `core/platform/cinemas_api.jac` (`owners_of`, `verification`), `core/theming/branding_api.jac` (`verified_at`), `web/platform/ReviewPages.jac`, `web/platform/PlatformConsole.jac`, `web/storefront/FooterInfo.jac` (the badge), `web/routes/VerifiedPage.jac` (its check), `web/backoffice/VerificationSection.jac`
- **Tests:** `tests/integration/review_tests.jac`, `tests/support/verification_setup.jac`, `tests/isolation/registry.jac`, `e2e/review_tests.jac`

## Context
14.4 lets an owner submit their details and documents (ADR-0070). Someone at AfriCinemas has to look at them and decide, and the decision has to reach the owner, and the storefront.

## Decision
1. **Who can review:** reviewers and super admins (`platform.review`). Support staff, and anyone off the platform, are refused.
2. **The queue:** **Reviews** in the console, with a count in the sidebar. It lists the cinemas waiting, oldest submission first.
3. **The review page:**
   - **Details:** the owner's and business's details side by side with the five files.
   - **Files:** each opens in the page, an ID photo as an image and a certificate as a PDF. Every opening is logged in the platform's audit log (`platform.verification_file_viewed`), because ID photos are personal data.
   - **Checklist:** the reviewer ticks five checks before Approve works:
     - the ID's name and number match the owner;
     - the registered name matches the certificates;
     - the KRA PIN matches its certificate;
     - the permit is current and names this business;
     - the address is in Kenya.
4. **Three decisions,** each in the platform's audit log and in the cinema's history:
   - **Approve:** the cinema goes from `ready_for_go_live` to `active` and is public. The approval date shows as **Verified cinema · checked by AfriCinemas on …** in its storefront's footer, under any design.
   - **Ask for changes:** reasons are required. The cinema goes back to `configuring`, and the owner's Verification page reopens with the reasons shown. They change what's asked and submit again.
   - **Reject:** reasons are required. The cinema stays private, and its page stays closed with the reasons. The owner can write to us from Help.

   A cinema that isn't waiting can't be decided on twice.
5. **A badge anyone can check.** The footer's badge is drawn by our code from our records, never by the cinema's design or text. But its look can be copied: words typed into a cinema's own text, or a look-alike site. So the badge is a link to `/verified/<slug>` on AfriCinemas' main address, which no cinema controls.
   - **A verified cinema:** the page confirms it, with the date and the cinema's one true address.
   - **Anything else** (unknown, private, not verified): the same answer, "We can't confirm this cinema… don't pay on it", naming nothing (`verified_cinema`).
   - **In the console:** the list of cinemas shows **Verified** (with the date) or **Waiting for review** beside each cinema.

   Every public cinema is verified anyway (only `active` is public, ADR-0064). The check is for copies.
6. **The owners are emailed** with the decision, its reasons and a link to their Verification page. The email is queued and sent by a job, as other emails are, to the owners' sign-in emails.
7. **The old Approve stays:** the cinema page's **Approve: make it public** (ADR-0064) remains, for the demo cinemas. A cinema that has submitted its details shows a link to its review instead of relying on it.

## Consequences
- **14.5b** adds the retention jobs decided before 14.4:
  - ID photos deleted 90 days after approval;
  - business documents deleted a year after a cinema closes;
  - support screenshots deleted 90 days after the request is closed.

  It also adds the badge in listings.
- The plain Approve can make a cinema public without a review. Once there are no demo cinemas left, it should go, or become super-admin only.
