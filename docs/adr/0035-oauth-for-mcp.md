# ADR-0035: Signing Claude in: our own OAuth 2.1 provider, discovery without a 401, and chat accounts

- **Status:** Accepted: confirmed in Claude on 2026-10-10 ("Sign in now": discovery, registration, consent, token, then MCP with the token)
- **Date:** 2026-10-10
- **Sub-phase:** P8.6a
- **Code:** `core/oauth/rules.jac`, `core/oauth/state.jac`, `core/oauth/accounts.jac`, `core/oauth/provider.jac`, `core/claims.jac` (`take_claim`), `core/mcp/server.jac` (`signed_in_customer`, `my_bookings`), `web/oauth/AuthorizePage.jac`, `web/auth/session.jac` (`safe_next`)
- **Tests:** `tests/unit/oauth_rules_tests.jac`, `tests/integration/oauth_tests.jac`, `tests/integration/claims_tests.jac`, the isolation registry

## Context
Booking from Claude needs the customer's own sign-in. MCP's authorization spec (2025-11-25) asks for OAuth 2.1 with PKCE S256, protected-resource metadata (RFC 9728), authorization-server metadata (RFC 8414), Client ID Metadata Documents or Dynamic Client Registration, and tokens bound to the MCP server. It also asks the MCP server to answer **401 with `WWW-Authenticate`** when a token is missing or bad.

Jac 0.37.18 can't do that last part (JI-033):
- a `@restspec(envelope=False)` function always answers 200, with no extra headers;
- no endpoint can read request headers.

What Jac can do: serve GET JSON, take form bodies, and run a request as the account whose Jac session token it carries.

## Decision
1. **Our own authorization server, in Jac, beside the MCP server** (user decision 2026-10-08).
   - Discovery: `/.well-known/oauth-authorization-server`, and `/.well-known/oauth-protected-resource` (also per path, for `/mcp` and each `/c/{slug}/mcp`).
   - Dynamic Client Registration at `POST /oauth/register`, with exact redirect URIs (https, or http to this machine).
   - A consent page at `/oauth/authorize`: the customer signs in, the page shows the app's name and the host they'll go back to, and Allow or Don't allow.
   - `POST /oauth/token` takes a form.
   - Client ID Metadata Documents are left out for now: fetching a URL a client names needs SSRF guards.
2. **Discovery instead of a 401.** Clients set to "sign in" read the discovery documents before calling MCP. Confirmed in Claude: two unsigned MCP calls, then `/.well-known/oauth-protected-resource/mcp`, `/.well-known/oauth-authorization-server`, `POST /oauth/register`, the consent page (S256, `resource` set), `POST /oauth/token`, then MCP with the token.
3. **Codes and refresh tokens are single-use, short-lived and never stored in the clear.**
   - Codes: 60 s, bound to the client, redirect URI, PKCE challenge, resource and the approving customer.
   - Refresh tokens: 30 days, rotated on every use.
   - Both are kept as SHA-256 and taken with `claims.take_claim`, one SQL statement that deletes only a live claim. So exactly one caller gets each, and never after it expires. A failed swap spends the code.
4. **Tokens belong to chat accounts, not customers.** The access token is a normal Jac session token, so Jac's own check runs MCP as its account. But that account is a separate one made for chat (random password, nobody signs in to it), linked to the customer, with no staff role anywhere. So:
   - MCP tools read the customer's own data by acting as the linked customer only inside those tools (`my_bookings`);
   - a token used against any other endpoint has a signed-out visitor's power, even when a cinema's owner signed in;
   - deleting the chat account voids its tokens.

## Consequences
- **Not fully compliant until Jac can send 401/`WWW-Authenticate` and read headers.**
  - A missing or expired token gets no challenge, just the signed-out tools.
  - Token-endpoint errors come back as 200 with an OAuth `error`, not 400.
  - Access tokens live as long as Jac sessions (days), not minutes. Rotation and the separate account limit the damage.

  An upstream Jac change (raw responses with status and headers, and request headers for functions) would close this.
- **Root ids come in two forms** (hex from the identity store, dashed from `node_id`): JI-044. `state.same_id` normalises them.
- **Next, 8.6b, if Claude signs in:**
  - booking from Claude (a booking card over the same hold, order and pay endpoints);
  - a page to see and revoke connections;
  - Client ID Metadata Documents.
