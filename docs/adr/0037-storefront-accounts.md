# ADR-0037: Storefront accounts belong to one cinema, apart from the back office

- **Status:** Accepted (supersedes decision 1 of ADR-0009)
- **Date:** 2026-10-10
- **Sub-phase:** P8.6c
- **Code:** `core/tenancy/storefront_accounts.jac`, `web/storefront/customer_session.jac`, `web/storefront/CustomerAuthPages.jac`, `web/storefront/AccountLinks.jac`, `core/oauth/provider.jac` (`cinema_of_resource`, `_customer_here`), `core/mcp/server.jac` (`signed_in_customer`)
- **Tests:** `tests/integration/storefront_accounts_tests.jac`, `tests/integration/customer_tests.jac`, `tests/integration/customer_tickets_tests.jac`, `tests/integration/oauth_tests.jac`, `e2e/my_tickets_tests.jac`

## Context
ADR-0009 gave everyone one platform login: a cinema owner and a moviegoer signed in on the same `/login`, and a moviegoer got a profile at each cinema they joined. Connecting Claude (P8.6a and b) showed what that means in practice: the consent page asked the customer to sign in "to AfriCinemas", with the back office's login, and an owner's account could book as a customer. The decision (2026-10-10) is that a storefront is the cinema's own product: its customers sign up and in on the cinema's website, in its branding, and nothing about it touches the back office.

## Decision
1. **A customer account belongs to one cinema.**
   - Customers sign up at `/c/<slug>/sign-up` and sign in at `/c/<slug>/sign-in`, inside the storefront's frame.
   - The same email can have a separate account, with its own password, at each cinema and as staff.
2. **Under Jac's one identity store, the account is a username, `<slug>:<email>`.**
   - It can never collide with a staff account's email identity or another cinema's customer.
   - Sign-up goes through our `customer_sign_up` endpoint, not Jac's `/user/register`. That is what lets the server record the account's cinema: a permanent claim `customer-account` on the account's root id holds `{slug, email, name}`.
3. **Walls, all on the server** (the cinema an account belongs to is never taken from the client):
   - `require_customer_of(slug)` guards joining a cinema as a customer, My tickets and saving a booking. Anyone else is refused `not_your_cinema`.
   - `require_staff_account()` guards creating a cinema and accepting a staff invitation. A customer account is refused `customer_account`.
   - Staff accounts are no one's customer.
4. **Claude connects to one cinema.**
   - The OAuth resource must be a cinema's connector, `/c/<slug>/mcp`. The platform-wide resource is gone.
   - Only that cinema's customer accounts can allow it, and its tokens are honoured only on that cinema's connector.
   - The consent page sends a signed-out visitor, or one signed in with another account, to that cinema's sign-in.
5. **The pages ask the server who the visitor is** (`my_storefront_account`), never the browser:
   - The storefront header shows Sign in, or My tickets and Sign out.
   - My tickets and "save to your account" offer this cinema's sign-in or sign-up.
   - The back office's `/login` and `/signup` no longer treat a signed-in customer account as one of theirs.
6. **The name a customer signs up with** names their profile when a booking is saved without one.

## Consequences
- The customer accounts made under ADR-0009 (email identities that joined a storefront) are now staff-shaped accounts and are no one's customer. There were no real customers yet, so nothing is migrated.
- One browser holds one Jac session. Signing in at one cinema signs the visitor out of any other account in that browser, including a staff one. This is acceptable for customers. Staff test their storefront in a private window.
- A customer who wants to book at two cinemas has two accounts. That is the intended product: each cinema owns its customer relationship.
- A future "one AfriCinemas login" (a marketplace across cinemas) would need a new ADR. The `<slug>:<email>` names keep that open, since a later identity can be linked to them.
