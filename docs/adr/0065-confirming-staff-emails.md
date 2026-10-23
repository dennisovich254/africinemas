# ADR-0065: Staff confirm their email with a one-time link

- **Status:** Accepted
- **Date:** 2026-10-23
- **Sub-phase:** P14.2
- **Code:** `core/accounts/email_verification.jac`, `core/tenancy/signup.jac` (the check in `create_cinema`), `web/auth/EmailCheck.jac` (the banner and `/verify-email`), `web/auth/SignupPage.jac`, `web/backoffice/NewCinemaWizard.jac`
- **Tests:** `tests/integration/email_verification_tests.jac`, `e2e/backoffice_tests.jac`, `e2e/support/api.jac` (`confirm_email_of`, `outbox_link`)

## Context
Anyone could sign up with someone else's email, or one they don't have, and create a cinema under it (threat model 3.3). Before a cinema goes public (Phase 14), we need to know its owner reads the email they gave: it's where we write to them, and part of who they are.

## Decision
1. **Our own link, not Jac's built-in verification.** Jac's `[serve.auth.email] verification` sends through its own mailer (`[scale.emailer]`), which isn't set up in development. It writes nothing to our development outbox, so neither a developer nor the browser tests could follow the link. Its email is fixed, unbranded text. In "required" mode it also blocks signing in altogether, where we only need to block creating and publishing a cinema. Ours uses the app's token store and our mail queue and job (as ticket emails do).
2. **The link** is `/verify-email#<token>` on the main site.
   - **Lifetime:** single use, valid 24 hours, and replaced by any newer link.
   - **Storage:** the token is made when the email is sent and kept only as a hash. The queue holds just the account and the address.
   - **Signed out:** confirming is public, so the link works signed out and on another device. The token in the fragment never reaches the server's logs.
   - **Limits:** sending is limited to five an hour per account, and only for the caller's own email (`verified_sign_in`).
3. **What it unlocks:** creating a cinema needs the owner's email confirmed. Submitting a cinema for review (14.4) will need it too, and that's the real gate.
   - **Accounts from before 14.2** aren't confirmed. They keep their cinemas and see the banner, but need to confirm before creating another.
   - **Accounts without an email** (a username, possible only outside the web sign-up) have nothing to confirm. They can create a cinema, but can never submit it for review, so it can never go public. The tests' actors are such accounts.
   - **The cinema's email** is sent by the page and checked as the caller's own on the server. A client that leaves it out gets a cinema whose owner has no email on record, which can't be submitted either.
4. **The screens:**
   - **After sign-up:** the first link goes at once, and the owner lands on Your cinemas.
   - **The banner:** "Confirm your email. We sent a link to … You'll need it to create a cinema and to go live", with **Send again**. It shows on Your cinemas and in the back office until the email is confirmed.
   - **The wizard:** it shows the refusal at the top of the form, not under the web address.
5. **Customer and platform accounts** sign in with usernames and never need this.

## Consequences
- Changing the email (account settings, improvements #13) must reset this and send a new link.
- With `AFRICINEMAS_SMTP_HOST` unset (development), the link is in the outbox (`.jac/outbox/*.eml` by default), like every email.
