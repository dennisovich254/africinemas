# AfriCinemas — Multi-Tenant Cinema SaaS Architecture

> **Revision note (2026-09-26).** This draft was reviewed against the actual Jac/Jaseci runtime (jaclang 0.37.x, built-in `scale` subsystem). The original draft assumed a hand-designed PostgreSQL schema-per-tenant stack with Redis, SQL constraints and cookie sessions. Jac does not work that way. Its persistence is a graph stored by the runtime in Postgres, auth is JWT-based, and concurrency is handled by SERIALIZABLE transactions with automatic replay. Sections marked **[Jac]** were rewritten or annotated to match what the platform really provides. Sections marked **[Fixed]** correct internal inconsistencies. Open questions that need a proof-of-concept before we commit are collected in **§138 Jac platform constraints and required spikes**.
>
> **Decisions (2026-09-26):**
> 1. **One shared Jac deployment for all tenants.** No per-tenant deployments or databases. Tenant isolation is purely logical (tenant subgraphs, grants, `authorize()`; §4). The silo tiers in §5/§133 are kept only as a documented future option and are **out of scope**.
> 2. **Jac is the committed stack.** This is a Jac hackathon project. The §138 spikes decide *how* to build each piece in Jac, not *whether* to use Jac.

This system is a **multi-tenant cinema SaaS platform**, not merely a ticket-booking website.

The core architectural principle is:

> **Tenant identity, authentication, authorization, and tenant isolation are four related but separate controls.**

AWS explicitly makes this distinction: an authenticated and authorized user can still reach another tenant’s resources unless tenant isolation is enforced independently. ([AWS Documentation](https://docs.aws.amazon.com/whitepapers/latest/saas-architecture-fundamentals/tenant-isolation.html "Tenant isolation - SaaS Architecture Fundamentals"))

The following architecture and requirements define a baseline for a production-grade system.

---

# 1. The overall platform

The platform really consists of **three products** sharing one backend:

```text
                         ┌───────────────────────────┐
                         │       PLATFORM CONTROL     │
                         │                           │
                         │ Tenant Registry            │
                         │ Identity / Memberships     │
                         │ Billing                    │
                         │ Domains                    │
                         │ Platform Operations        │
                         └────────────┬──────────────┘
                                      │
                     ┌────────────────┴────────────────┐
                     │                                 │
              ┌──────▼──────┐                  ┌──────▼──────┐
              │ PUBLIC       │                  │ ADMIN       │
              │ STOREFRONT   │                  │ PORTAL      │
              │              │                  │             │
              │ Movies       │                  │ Employees   │
              │ Shows        │                  │ Screens     │
              │ Seats        │                  │ Movies      │
              │ Booking      │                  │ Revenue     │
              │ Payment      │                  │ Reports     │
              │ QR Tickets   │                  │ Settings    │
              └──────┬───────┘                  └──────┬──────┘
                     │                                   │
                     └────────────────┬──────────────────┘
                                      │
                            ┌─────────▼─────────┐
                            │   TENANT-AWARE    │
                            │   APPLICATION     │
                            │                   │
                            │ Auth/AuthZ         │
                            │ Booking            │
                            │ Ticketing           │
                            │ Payments            │
                            │ Cinema Operations   │
                            │ Notifications       │
                            └─────────┬─────────┘
                                      │
          ┌───────────────────────────┼───────────────────────────┐
          │                           │                           │
   ┌──────▼──────┐             ┌──────▼──────┐            ┌──────▼──────┐
   │ PostgreSQL  │             │ Jac outbox/ │            │ Object      │
   │ (Jac graph  │             │ scheduler   │            │ Storage     │
   │  store)     │             │ Jobs/Events │            │ Posters     │
   └─────────────┘             └─────────────┘            └─────────────┘
                                      │
                               ┌──────▼──────┐
                               │ Integrations│
                               │ M-Pesa      │
                               │ eTIMS       │
                               │ Email/SMS   │
                               └─────────────┘
```

The first production version should **not start with dozens of microservices**.

A well-structured Jac modular monolith with clear domain boundaries, PostgreSQL, background workers, object storage, WAF/CDN and a secrets manager is much easier to secure and operate. Services can later be extracted where there is a genuine scaling or isolation requirement.

**[Jac]** Concretely for V1:

- **PostgreSQL** is the Jac runtime's graph store (embedded locally, `JAC_DB_URL` in production). We do not design tables or schemas ourselves.
- **Background work** uses Jac's built-in pieces: `on_commit(...)` for side effects that must fire once, the outbox for at-least-once deferred walkers, and the `[scale.scheduler]` subsystem for periodic jobs. No separate queue product is needed in V1.
- **Redis is not part of V1.** Seat holds, idempotency records and per-customer quota counters live in the database (coarse per-IP rate limiting lives at the edge, §58), which §25 already names as the source of truth. Redis can be added later as a cache, with the tenant-prefixed keys described in §6.
- **Domain boundaries** are separate Jac modules (`tenancy/`, `catalog/`, `booking/`, `payments/`, `ticketing/`, `platform/`). They can later become Jac *service apps* (`[apps.<name>] kind = "service"`) without rewriting call sites, because cross-app calls are typed async bridges.

---

# 2. The tenant model

The fundamental hierarchy should be something like:

```text
Platform
   │
   ├── Tenant / Cinema Operator
   │      │
   │      ├── Owner
   │      ├── Employees
   │      ├── Venues
   │      │     ├── Auditorium 1
   │      │     ├── Auditorium 2
   │      │     └── Auditorium 3
   │      │
   │      ├── Movies
   │      ├── Showtimes
   │      ├── Seat layouts
   │      ├── Bookings
   │      ├── Tickets
   │      ├── Payments
   │      ├── Promotions
   │      ├── Loyalty
   │      └── Reports
   │
   └── Other tenants...
```

Every meaningful resource belongs to a tenant.

For example:

```text
tenant
venue
auditorium
seat
seat_layout
movie
showtime
booking
booking_seat
ticket
payment
refund
promotion
employee
customer
concession_order
inventory
audit_event
```

The critical rule is:

```text
resource.tenant_id == authenticated_context.tenant_id
```

or, in a schema-isolated model:

```text
current tenant -> correct schema
```

Tenant context should still flow through the application even when schemas are physically separate.

AWS specifically recommends making tenant context part of the application's identity and allowing that context to flow through the application into downstream resources. ([AWS Documentation](https://docs.aws.amazon.com/whitepapers/latest/saas-tenant-isolation-strategies/identity-and-isolation.html "Identity and isolation - SaaS Tenant Isolation Strategies: Isolating Resources in a Multi-Tenant Environment"))

---

# 3. Tenant owner and administrative identity model

The proposed tenant owner model:

> Cinema owner creates the cinema account → becomes root/owner → creates employees

is a good starting point. (Note: "root" here means *top of the tenant's role hierarchy*. It is **not** the Jac `root` node. In Jac every user, owner or not, has their own personal `root`, and tenant data must not hang off it; see §4.)

However, **do not model it as an unrestricted superuser that employees can casually inherit**.

Think of it as:

```text
Tenant Owner
    │
    ├── owns tenant
    ├── can configure tenant
    ├── can create administrators
    ├── can configure payment
    ├── can delete/deactivate tenant
    └── can perform sensitive financial actions
```

AWS itself recommends that the root identity be protected and not used for everyday administration; normal operations should use separately managed administrative identities. ([AWS Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/root-user-best-practices.html "Root user best practices for your AWS account - AWS Identity and Access Management"))

The administrative hierarchy should be:

```text
Tenant Owner
   ↓
Tenant Administrators
   ↓
Custom Roles
   ↓
Employees
```

And separately:

```text
Platform Super Admin
Platform Support
Platform Security
Platform Finance
Platform Operations
```

**Never mix the platform administrator hierarchy with a cinema's tenant administrators.**

---

# 4. Tenant isolation — the most important architectural decision

AWS describes three broad SaaS isolation models:

- **Pool** — tenants share infrastructure.
- **Silo** — tenants receive dedicated infrastructure.
- **Bridge** — combination of both.

AWS specifically describes the bridge model as useful when different resources have different isolation requirements. ([AWS Documentation](https://docs.aws.amazon.com/wellarchitected/latest/saas-lens/silo-pool-and-bridge-models.html "Silo, Pool, and Bridge Models - SaaS Lens"))

The cinema platform should use a **bridge architecture**.

## Recommended starting model **[Jac]**

> The original draft proposed **schema-per-tenant PostgreSQL**. That cannot be built on Jac. The Jac runtime owns the storage layout: every node and edge is a row in the runtime's own Postgres store, and there is no API for placing one tenant's archetypes in a separate schema. Trying to bypass the runtime (raw SQL, a second ORM) would throw away OSP persistence, grants and the transaction and replay guarantees this design depends on (§25). The isolation model below is the Jac-native equivalent.

```text
                         PLATFORM CONTROL GRAPH
                  (owned by the platform system identity)
         Tenant registry · domains · memberships · subscriptions
                                  │
             ┌────────────────────┼────────────────────┐
             │                    │                    │
       TenantA (node)       TenantB (node)       TenantC (node)
       owned by tenant-A    owned by tenant-B    owned by tenant-C
       service principal    service principal    service principal
             │                    │                    │
   Venues → Auditoriums → SeatLayouts → Screenings → SeatSlots → Bookings → Tickets …
   (the whole operational subgraph hangs off its Tenant node)
```

### Layer 1: ownership (graph boundary)

- Every tenant's operational data is a **subgraph rooted at its `Tenant` node**. Nothing is shared between tenant subgraphs, and no edge ever crosses from one tenant's subgraph into another's.
- The subgraph is **owned by a per-tenant service principal**, not by the cinema owner's personal account. In Jac the owner of a node always keeps WRITE access, and that cannot be taken away. Letting a human's root own the tenant would make "Changing owner" (§16) and owner offboarding impossible to do safely.
- Staff reach the subgraph through **group grants**: one `StaffGroup` node per tenant, a `MemberOf` edge per employee, and `allow_group(node, group, level)` applied by a single helper (`_attach_to_tenant`) whenever a tenant node is created. Grants are **per node, not per subtree**, so every creation path must go through that helper. A lint or test enforces this (§112).
- **Never use archetype-wide `__jac_access__` on tenant data.** It opens *every instance of the type*, across *every* tenant. It is only acceptable for platform-owned public structure.

### Layer 2: tenant context (application boundary)

Every protected endpoint builds a request-scoped `TenantContext` before touching data:

```text
Request
 ↓
Authenticated user (JWT → caller's root)
 ↓
Tenant selector (hostname/slug; a hint, NOT authority, see §7)
 ↓
Membership lookup: caller root -[MemberOf]-> StaffGroup -> Tenant
 ↓
TenantContext { tenant_jid, member_jid, role_ids, permission_set, venue_scope }
 ↓
authorize(ctx, action, resource)   (§129)
 ↓
Traverse FROM the Tenant node to the resource
```

### Never do this (Jac edition)

```text
def:priv get_booking(booking_id: str) {
    b = jobj(booking_id);        # resolves ANY node in the database
    return b;                    # BOLA: cross-tenant read
}
```

`jobj(jid)` resolves a node **regardless of grants or tenant**. It is the Jac equivalent of `SELECT * FROM bookings WHERE id = ?` with no tenant filter. Client-supplied IDs must be resolved **by traversal from the caller's `Tenant` node** (or resolved with `jobj` and then proven reachable from it) before any read or write. See §51.

### Shared control plane

The control plane is a platform-owned subgraph holding:

```text
Tenant
TenantDomain
TenantMembership (MemberOf edges + role assignments)
Role / Permission definitions
Subscription / PlatformBilling
FeatureFlags
TenantProvisioning state
```

### Public catalogue

Anonymous storefront visitors run on Jac's shared guest graph (`root.shared`). Published, non-sensitive data (movies, screenings, seat-map geometry, prices) is **projected** into a per-tenant `Storefront` node on `root.shared` when it is published. The operational subgraph is never exposed directly. The projection is read-only to the public (`grant(..., AccessLevel.READ)`), and only the publishing workflow writes to it.

---

# 5. Should you eventually use database-per-tenant?

Have a migration path.

| Model **[Jac]**                                                      | Security isolation                                | Operational complexity | Cost      | Scaling   |
| -------------------------------------------------------------------- | ------------------------------------------------- | ---------------------- | --------- | --------- |
| Shared deployment, all tenant data owned by one system identity      | Weak: isolation rests on app code alone            | Low                    | Low       | Excellent |
| Shared deployment, per-tenant service principal + group grants (**V1**) | Good: ownership + grants + `authorize()`         | Medium                 | Low       | Excellent |
| Dedicated Jac deployment per tenant (own `JAC_DB_URL`)               | Very strong (separate database)                   | High                   | High      | Moderate  |
| Dedicated deployment + dedicated cluster/account                     | Strongest                                          | Very high              | Very high | Difficult |

AWS explicitly says the appropriate model depends on compliance, cost, scaling, operational burden and domain requirements rather than prescribing one universal solution. ([AWS Documentation](https://docs.aws.amazon.com/whitepapers/latest/saas-tenant-isolation-strategies/silo-for-any-resource.html "Silo for any resource - SaaS Tenant Isolation Strategies: Isolating Resources in a Multi-Tenant Environment"))

The application should therefore use:

```text
Normal tenants
    ↓
Shared Jac deployment
    ↓
Tenant subgraph + service principal + group grants

Large/enterprise tenant
    ↓
Dedicated Jac deployment (same code, own database)

Exceptional high-security tenant
    ↓
Dedicated infrastructure
```

The control plane remains shared.

**Decision:** we build and run **one shared deployment** only. The dedicated-deployment tiers above are a documented future option, not part of this project. If one is ever needed, it would be the same codebase deployed with its own `JAC_DB_URL`, with the edge routing that tenant's hostname to it. Note that user identities are per deployment, so a person working at tenants in two deployments would need two accounts unless a shared external IdP is introduced.

That gives you a natural **tenant isolation tiering strategy**.

---

# 6. Use defense-in-depth

Do not rely on one isolation mechanism.

The system requires:

```text
Hostname isolation
        +
Identity tenant binding
        +
Authorization
        +
Application tenant context
        +
Database isolation
        +
Storage isolation
        +
Cache isolation
        +
Queue isolation
        +
Search isolation
        +
Logging isolation
```

For example, a cache (Redis or otherwise, if one is introduced) must not have:

```text
seat:123
```

Instead:

```text
tenant:{tenant_id}:show:{showtime_id}:seat:{seat_id}
```

Likewise:

```text
cache:tenant-A:movies
cache:tenant-B:movies
```

And queues/events should contain:

```json
{
  "tenant_id": "...",
  "event_type": "BOOKING_CONFIRMED",
  "booking_id": "..."
}
```

A background worker must re-establish tenant context before accessing data.

---

# 7. Tenant context must never come from the client

Do **not** trust:

```http
X-Tenant-ID: cinema-123
```

from a browser.

Instead:

```text
Request Host
      ↓
cinema-123.yourplatform.com
      ↓
lookup tenant domain
      ↓
Tenant = UUID(...)
      ↓
authenticate user
      ↓
check membership in that tenant
```

For customer/public requests, the hostname itself establishes the storefront.

**[Fixed] Selector vs authority.** The rule is not "the tenant ID must never be sent by the client". The rule is "**a client-supplied tenant value is only a selector, never an authority**":

- For **public, published data** (the storefront catalogue), a tenant slug from the client just picks which public projection to read. Sending another cinema's slug only shows that cinema's public page, which anyone can see anyway.
- For **anything authenticated**, the server resolves the tenant from the selector and then **proves the caller's membership** (staff) or **resource ownership** (customer) before acting. A forged `X-Tenant-ID` then fails the membership check instead of leaking data.

**[Jac] Reading the Host header.** Jac endpoints (`def:pub`, walkers) receive typed parameters, not the raw request. Only underscore middleware walkers (`_before_request`) see the request dict. Two workable designs:

1. **Edge-resolved (recommended):** the reverse proxy/CDN (Cloudflare, nginx) maps `Host → tenant slug` against the verified-domain allowlist and forwards it in a header it overwrites itself (clients can never set it). `[serve.proxy] trusted` must list only that proxy.
2. **Client-passed selector:** the storefront bundle passes its own hostname/slug as a parameter. This is acceptable because of the selector-vs-authority rule above.

Which of these the runtime supports cleanly (in particular, whether `_before_request` can hand a value to the endpoint) is a spike item in §138.

For example:

```text
imaxnairobi.yourcinema.com
```

maps to:

```text
tenant_id = 8b7...
```

The customer cannot simply modify a request parameter and access:

```text
anothercinema.yourcinema.com
```

---

# 8. Custom domains and subdomains

Initially:

```text
cinema-name.platform.co.ke
```

or:

```text
cinema-name.yourplatform.com
```

Later:

```text
www.cinemaname.co.ke
```

could point to the platform.

The domain service requires:

```text
tenant_domains
----------------
id
tenant_id
hostname
type
verification_status
verified_at
ssl_status
```

For custom domains:

```text
Customer enters:
tickets.cinema.co.ke

        ↓

Platform generates verification token

        ↓

Customer adds TXT record

        ↓

Platform verifies ownership

        ↓

Domain becomes ACTIVE

        ↓

TLS certificate provisioned
```

Never activate a claimed domain merely because someone typed it into the dashboard.

Custom-domain SaaS platforms commonly use domain verification and automated certificate provisioning. ([Cloudflare Developer Docs](https://developers.cloudflare.com/use-cases/saas/custom-domains/ "Customer domains with SSL for SaaS · Cloudflare use cases"))

### Important security issue: subdomain takeover

When a tenant leaves, remove/deactivate its DNS mapping before releasing underlying resources.

OWASP explicitly identifies dangling DNS records as a route to subdomain takeover, potentially allowing attackers to host arbitrary content under a trusted domain and interfere with cookies, OAuth/SSO and phishing protections. ([OWASP Cheat Sheet Series](https://cheatsheetseries.owasp.org/cheatsheets/Subdomain_Takeover_Prevention_Cheat_Sheet.html "Subdomain Takeover Prevention - OWASP Cheat Sheet Series"))

Also:

- maintain DNS inventory
- prevent dangling records
- validate hostname ownership
- monitor certificate issuance
- don't allow arbitrary CNAME targets
- reject malformed hostnames
- do not use wildcard routing without an application-level hostname allowlist
- ensure deleted tenants become inaccessible immediately

---

# 9. Authentication architecture

The system has two identity populations.

## Cinema staff

High-security:

```text
Owner
Admin
Finance
Manager
Box Office
Concessions
Content Manager
Usher
Auditor
IT
```

## Customers

Lower-privilege:

```text
Customer
```

The identity system should therefore support:

```text
User
TenantMembership
Role
Permission
Session
Authenticator
RecoveryMethod
```

A user can potentially belong to multiple cinemas:

```text
User
 ├── Tenant A / Manager
 ├── Tenant B / Auditor
 └── Tenant C / Owner
```

That is much more flexible than:

```text
user.tenant_id
```

on the user record.

---

# 10. MFA

For tenant owners and administrators:

**MFA should be mandatory.**

Prefer:

```text
Passkey / WebAuthn
```

then:

```text
TOTP authenticator
```

as fallback.

Recovery codes should be generated once, shown to the user once, and **stored only as hashes** (like passwords), with each code single-use.

**[Jac]** The built-in Jac auth (`/user/register`, `/user/login`) provides username/email + password and SSO. It does **not** provide MFA, TOTP or passkeys. Options:

- **V1:** app-level TOTP (e.g. `pyotp` via Python interop). The secret is stored encrypted, the authenticator is enrolled by the owner and admins, and TOTP is verified **inside every sensitive endpoint as a step-up parameter** (§16). This works without session support from the runtime.
- **Later:** move staff authentication to an external IdP (Keycloak, Auth0, Entra, etc.) through `[scale.sso]`/OIDC, which supplies passkeys and enforced MFA.

NIST's current digital identity guidance emphasizes replay resistance and phishing-resistant authentication for higher assurance authentication. ([NIST Pages](https://pages.nist.gov/800-63-4/sp800-63b.html "NIST Special Publication 800-63B")) AWS also recommends phishing-resistant MFA such as passkeys/security keys where possible. ([AWS Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html "Security best practices in IAM - AWS Identity and Access Management"))

---

# 11. Customer authentication

Customers could use:

```text
Email + password
Email magic link
Passkey
Phone + OTP
```

SMS OTP should not be the only high-security mechanism.

Customer accounts should have:

```text
email_verified
phone_verified
last_login
sessions
devices
marketing_consent
```

A cinema booking should not require collecting unnecessary personal information.

---

# 12. Password security

Never store:

```text
password = plaintext
```

Use a modern password hashing scheme such as:

```text
Argon2id
```

with appropriate parameters.

Do not implement custom password encryption.

Password reset tokens should be:

```text
random
single-use
short-lived
stored hashed
invalidated after use
```

The response to:

```text
forgot-password?email=...
```

should not reveal whether an account exists.

OWASP's authentication guidance emphasizes secure authentication, account recovery, logging and protection against authentication attacks. ([OWASP Cheat Sheet Series](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html "Authentication - OWASP Cheat Sheet Series"))

---

# 13. Session security

For browser applications, the preferred approach is:

```text
Secure
HttpOnly
SameSite
host-only session cookies
```

rather than storing long-lived authentication tokens in `localStorage`.

Particularly important in this architecture:

### Do not share an authentication cookie across every tenant subdomain.

Bad:

```text
Domain=.yourplatform.com
```

because compromise of one tenant's storefront could become much more serious.

Prefer host-specific authentication contexts.

Admin authentication should also be on a separate administrative origin where practical.

**[Jac] What the runtime really does.** Jac auth issues **bearer JWTs**. The Jac client stores the token in `localStorage` (`jac_token`) and sends it as `Authorization: Bearer`. Documented limitations: **no token revocation** (tokens stay valid until expiry) and **no refresh-token rotation** (refresh issues a new token without invalidating the old one). Default TTL is 7 days. Consequences:

- The "HttpOnly cookie, not localStorage" ideal above is **not met by the stock client**. XSS on a storefront could steal a token, which makes §55 (no tenant JavaScript) and a strict CSP (§61) **mandatory, not optional**.
- Set `[serve.auth] token_ttl_days` low for staff (target ≤ 1 day; see §138 for sub-day TTLs).
- "Log out all devices" (§83) and "invalidate on role removal" must be **enforced by the app**. On every privileged call, re-check membership and role against the graph (never trust role claims cached on the client). Removing a membership then takes effect immediately even though the JWT is still valid.
- `[serve.auth] secret` **must** be set in every non-dev environment. Without it, clusters fall back to a shipped placeholder and anyone can forge tokens.
- Host-only tokens: because the token sits in per-origin `localStorage`, it is naturally not shared across tenant subdomains, which satisfies the "don't share across subdomains" rule above.

---

# 14. Authorization

RBAC alone is not enough.

Use:

```text
RBAC + tenant scope + resource scope + sensitive-action rules
```

For example:

```text
Finance Manager
  CAN:
    view revenue
    export financial reports
    initiate refund

  CANNOT:
    manage employee roles
    configure M-Pesa credentials
    delete tenant
```

OWASP recommends least privilege and deny-by-default authorization. ([OWASP Cheat Sheet Series](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html "Authorization - OWASP Cheat Sheet Series"))

---

# 15. Recommended cinema roles

Start with built-in roles, then allow custom roles.

**[Fixed]** The original list had a tenant-level `SUPER_ADMIN`, which collides with *Platform Super Admin* (§3 says never mix the two hierarchies). It is renamed `TENANT_ADMIN`. Also do **not** map any tenant role onto Jac's built-in platform roles (`admin` / `system` / `user`). Jac `admin` unlocks the runtime admin portal at `/admin` and user management for the **whole deployment**, so it is reserved for platform break-glass only (§17).

```text
OWNER
TENANT_ADMIN
GENERAL_MANAGER
FINANCE_MANAGER
BOX_OFFICE_MANAGER
BOX_OFFICE_AGENT
CONTENT_MANAGER
CONCESSION_MANAGER
INVENTORY_MANAGER
USHER
AUDITOR
MARKETING_MANAGER
IT_ADMIN
```

Example permissions:

```text
movies.read
movies.create
movies.update
movies.publish

showtimes.read
showtimes.create
showtimes.update
showtimes.cancel

seats.read
seats.configure

bookings.read
bookings.create
bookings.cancel

tickets.issue
tickets.invalidate
tickets.scan

payments.read
payments.refund
payments.reconcile

financial_reports.read

employees.read
employees.invite
employees.disable
employees.assign_roles

tenant.settings.update
tenant.payment_settings.update
tenant.delete
```

---

# 16. Sensitive operations need step-up authentication

Even if someone is already logged in, require fresh authentication/MFA for:

```text
Changing M-Pesa credentials
Changing Paybill
Adding another administrator
Changing owner
Issuing large refunds
Bulk ticket cancellation
Changing tax configuration
Changing domain
Deleting tenant
Exporting large PII datasets
Rotating payment credentials
```

This limits damage after session theft.

---

# 17. Platform administrators

There must be a separate platform-level administration plane.

```text
Platform Admin
    ↓
All tenants
```

while:

```text
Cinema Owner
    ↓
ONE tenant
```

The platform administrator should never accidentally inherit the same permission model as a cinema employee.

**[Jac]** Platform staff roles (support, finance, security, operations) are modelled in the **platform control graph**, like tenant roles. They are *not* the Jac built-in `admin` role. Jac `admin` gives the runtime admin portal (`/admin`), `PUT /admin/users/...` and `/metrics`. Hold it with at most one or two break-glass identities, MFA'd at the IdP, and audit every use.

Platform admin capabilities might include:

```text
tenant provisioning
tenant suspension
support
subscription management
system health
payment integration monitoring
security investigation
fraud investigation
platform analytics
```

---

# 18. Impersonation

Eventually support will ask:

> "Can you see what the cinema owner is seeing?"

Build controlled impersonation, but **make it highly auditable**.

For example:

```text
Support Admin
    ↓
Request impersonation
    ↓
reason required
    ↓
time-limited session
    ↓
read-only by default
    ↓
every action logged
```

Never create an invisible "login as user" shortcut.

---

# 19. Cinema domain model

The core domain should include approximately these entities:

```text
Tenant
User
TenantMembership
Role
Permission

Venue
Auditorium
SeatLayout
Seat
SeatZone
SeatType

Movie
MovieMedia
Genre
Language
AgeRating

Screening            (was "Showtime"; see §119)
ScreeningPricing
TicketType
SeatSlot             (one per Screening × Seat; the unit of seat inventory, §25)

SeatHold
Order                (commercial envelope; §78)
Booking
BookingItem
Ticket

PaymentAccount       (§30)
PaymentIntent
PaymentTransaction
Refund
Settlement
ReconciliationRecord
LedgerEntry          (§37)
IdempotencyRecord    (§26)

Promotion
Coupon
LoyaltyAccount
LoyaltyTransaction

ConcessionProduct
ProductCategory
Inventory
InventoryTransaction
ConcessionOrder

Employee
Device
ScannerDevice

Notification
NotificationMessage  (channel = EMAIL | SMS | PUSH; not separate Email/SMS entities)

TaxInvoice
TaxInvoiceItem

GiftCard / GiftCardTransaction   (§118)
TenantDomain                     (§8)
StaffGroup                       (Jac grant group per tenant; §4)

AuditEvent
SecurityEvent
```

**[Fixed]** The original list was missing entities introduced later in the document (`Order`, `LedgerEntry`, `PaymentAccount`, `GiftCard`, `TenantDomain`) and modelled `Email`/`SMS` as separate entities. It also used "Session" in §119 for screenings while §9 uses "Session" for login sessions. Screenings are now called `Screening` everywhere, and "session" only ever means an authentication session.

---

# 20. Venues and multiple locations

Do not assume one cinema account = one physical location.

A tenant might eventually own:

```text
Company ABC
 ├── Nairobi
 │    ├── Screen 1
 │    ├── Screen 2
 │    └── Screen 3
 │
 ├── Mombasa
 │    ├── Screen 1
 │    └── Screen 2
 │
 └── Kisumu
      └── Screen 1
```

Permissions should therefore optionally support:

```text
Tenant scope
Venue scope
Auditorium scope
```

For example:

```text
Mombasa Manager
```

doesn't automatically gain access to:

```text
Nairobi revenue
```

---

# 21. Seat layout designer

This deserves its own subsystem.

The admin should visually build:

```text
                SCREEN
─────────────────────────────────

 A01 A02 A03      A04 A05 A06
 A07 A08 A09      A10 A11 A12

 B01 B02 B03      B04 B05 B06

 C01 C02 C03      C04 C05 C06

      ♿    aisle

 D01 D02 D03 D04 D05 D06
```

Support:

### Seat types

```text
STANDARD
PREMIUM
VIP
RECLINER
COUPLE
WHEELCHAIR
COMPANION
SOFA
BLOCKED
HOUSE
```

### Layout attributes

```text
row label
seat number
position
rotation
seat type
zone
accessible flag
blocked flag
price category
screen-relative coordinates
```

### Physical structures

```text
aisles
stairs
entrances
exits
screen
walls
columns
wheelchair areas
emergency routes
```

### Pricing zones

For example:

```text
Standard Zone     KES 500
Premium Zone      KES 700
VIP Recliner      KES 1,200
Couple            KES 1,800
```

---

# 22. Never mutate historical seat layouts

This is important.

Suppose:

```text
Screen 1
Layout V1
```

was used for a show on September 20.

Screen 1 is redesigned on September 25.

Do **not** overwrite V1.

Instead:

```text
Screen 1
 ├── Layout V1
 │    └── historical shows
 │
 └── Layout V2
      └── future shows
```

This preserves historical ticket records.

---

# 23. Booking engine

This is one of the highest-risk components.

The biggest technical problem is:

> Two customers choose the same seat simultaneously.

Example:

```text
Customer A -> seat A10
Customer B -> seat A10
```

A transactional seat reservation mechanism is required.

**[Fixed]** The original draft mixed seat, booking and ticket states into one chain (`AVAILABLE → HELD → PAYMENT_PENDING → BOOKED → TICKET_ISSUED → USED`) and then defined *different* booking and ticket lifecycles in §122/§123 (`BOOKED` vs `CONFIRMED`, a ticket that was `RESERVED`/`PAID`). There are **four separate state machines, each owned by one entity**:

```text
SeatSlot (per screening × seat):   AVAILABLE ⇄ HELD → SOLD
                                   BLOCKED / HOUSE (set by staff, not sellable online)
                                   SOLD → AVAILABLE only via refund/void (§38)

Booking:                           §123
Payment:                           §32
Ticket:                            §122
```

A booking *references* SeatSlots. It does not own seat state. Payment success moves the Booking to CONFIRMED and the SeatSlots from HELD to SOLD **in the same transaction**.

---

# 24. Seat holds

When a customer selects a seat:

```text
Seat A10
      ↓
temporary hold
      ↓
hold expires
      ↓
seat available again
```

Store:

```text
hold_id
tenant_id
showtime_id
seat_id
booking_id
customer_id
expires_at
status
```

The client timer is purely visual.

**The server decides whether the hold has expired.**

**[Fixed] Holds vs slow M-Pesa payments.** An STK push can take a minute or more (the customer has to find their phone and enter their PIN), and Daraja callbacks can arrive late. The original draft did not cover this race: the hold expires, the seat is resold, and *then* the first customer's payment succeeds. Rules:

1. When payment is initiated, the hold's `expires_at` is **extended to the payment timeout plus a grace period**, and the hold enters `PAYMENT_PENDING`. The expiry sweeper never releases a `PAYMENT_PENDING` hold. Only a terminal payment state (FAILED / CANCELLED / TIMEOUT, confirmed via status query) releases it.
2. If a **late SUCCESS** arrives for a booking whose hold was already released and resold, the payment is still recorded (money moved). The booking goes to `NEEDS_ATTENTION` and follows an **automatic refund-or-reseat policy**. It is never silently dropped.
3. Each customer has a cap on concurrently held seats per screening (anti-scalping, §59).

**[Jac]** Expiry is **lazy + swept**. Every read of a SeatSlot treats `HELD && expires_at < now && !payment_pending` as AVAILABLE, and a scheduled job (`@schedule`, §74) cleans up. Correctness never depends on the sweeper running on time.

Never trust:

```javascript
countdown === 0
```

as the security mechanism.

---

# 25. Database transaction for seats

The database remains the source of truth.

For example conceptually:

```text
BEGIN

lock seat/showtime inventory

verify seat is still available

create hold

commit
```

or use appropriate unique constraints/transaction isolation so two concurrent booking requests cannot both obtain the same seat.

Redis can accelerate temporary state, but it should **not be the ultimate source of truth for ticket ownership**.

**[Jac] How this works on Jac.** There are no explicit locks and no `SELECT … FOR UPDATE`. Instead, **every request runs in one Postgres transaction at SERIALIZABLE isolation**. When two requests race on overlapping data, one commits and the other is rolled back and **replayed from the start** (default `on_conflict = "retry"`, up to `conflict_max_attempts = 5`, then HTTP 409). So the seat-hold algorithm is plain code:

```text
hold_seats(ctx, screening_jid, seat_jids[]):
    for each SeatSlot reached FROM ctx.tenant → screening:
        if slot.state != AVAILABLE (after lazy expiry) → fail whole request
    set each slot.state = HELD, create SeatHold
    return hold
```

Two customers racing for A10 both read AVAILABLE, but only one transaction commits. The loser replays, sees HELD and fails cleanly. Design consequences:

- **One node per (screening × seat), the `SeatSlot`.** Never keep seat availability as a dict or list on the Screening node. That turns every hold on the screening into a write to one hot row, so every concurrent booking conflicts and replays, and an opening-night release would degrade into a 409 storm.
- **Anything external inside a replayable request must go through `on_commit(...)`** (see §29). A replayed request re-runs its code, so an SMS or STK push sent inline would be sent once per attempt.
- Set `on_conflict = "fail"` only for endpoints whose clients handle 409 themselves.

---

# 26. Booking idempotency

Customer clicks:

```text
Pay
```

Then their mobile network freezes.

They click again.

Without idempotency you can create:

```text
Order A
Order B
```

and potentially two payments.

Use an idempotency key:

```text
Idempotency-Key: UUID
```

for operations such as:

```text
create booking
initiate payment
refund payment
issue ticket
```

The server stores the result associated with that idempotency key.

**[Jac]** Implement it as an `IdempotencyRecord` node keyed by `(tenant, caller, key)`, created with the *find-or-create* pattern. Under SERIALIZABLE + replay, two concurrent requests with the same key converge on one record, and the second returns the stored result. Keys expire (e.g. 24h) through a scheduled sweep. This complements the transport-level idempotency that Jac's outbox already provides for deferred cross-app calls (`X-Jac-Idempotency-Key`).

---

# 27. Price snapshotting

At payment time:

```text
Adult ticket
price = KES 800
```

The order should store the price that was actually quoted.

Do not calculate today's price again when reconciling yesterday's order.

Store:

```text
unit_price
discount
tax
service_fee
total
currency
pricing_rule_id
```

---

# 28. Cinema pricing engine

Eventually you will need:

```text
Adult
Child
Student
Senior
Member
VIP
3D surcharge
Weekend
Public holiday
Premiere
Morning show
Late night
Premium auditorium
Online booking fee
Promotional pricing
```

And possibly:

```text
specific movie
specific venue
specific auditorium
specific showtime
specific seat zone
```

Therefore pricing should be a proper domain service rather than:

```text
showtime.price
```

---

# 29. M-Pesa architecture

This deserves exceptional care.

Safaricom's **Daraja 3.0** provides APIs for connecting M-Pesa services to web/mobile applications. ([daraja.safaricom.co.ke](https://daraja.safaricom.co.ke/ "Daraja Developer Portal | Safaricom"))

The architecture should be:

```text
Customer
   │
   │ selects seats
   ▼
Cinema storefront
   │
   ▼
Booking Service
   │
   │ creates payment intent
   ▼
Payment Service
   │
   ▼
Safaricom Daraja
   │
   ▼
Customer's M-Pesa phone
   │
   ▼
M-Pesa result
   │
   ▼
Webhook
   │
   ▼
Payment Service
   │
   ▼
Booking confirmed
   │
   ▼
QR ticket
```

**[Jac] Critical: never call Daraja inside the request body.** Because a request can be replayed after a serialization conflict (§25), an STK push made inline could be sent **two or more times**, and the customer would get several PIN prompts and possibly several charges. The correct shape:

```text
initiate_payment (one transaction):
    create PaymentIntent(state=CREATED, idempotency key)
    extend hold → PAYMENT_PENDING
    on_commit( enqueue STK push job for this PaymentIntent )   # fires once, only if committed

STK worker (separate unit of work):
    call Daraja STK Push (with our own idempotent reference)
    record CheckoutRequestID, state=STK_REQUESTED
```

---

# 30. Very important: don't treat Paybill credentials as ordinary settings

The cinema owner enters:

```text
Paybill number
```

But the payment configuration should conceptually be:

```text
PaymentAccount
-----------------
tenant_id
provider = MPESA
shortcode
account_type
credential_reference
environment
status
verified_at
last_test_at
```

Never:

```text
tenant.mpesa_password = "..."
```

in normal application tables.

Secrets should live in:

```text
AWS Secrets Manager
Azure Key Vault
GCP Secret Manager
HashiCorp Vault
```

or another equivalent secrets management system.

OWASP specifically recommends centralized secret storage, least-privilege access, rotation, revocation and ensuring secrets never appear in logs. ([OWASP Cheat Sheet Series](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html "Secrets Management - OWASP Cheat Sheet Series"))

---

# 31. The cinema should remain the merchant receiving the money

The preferred architecture is:

```text
Customer
   ↓
Cinema's configured M-Pesa Paybill
   ↓
Cinema receives funds
```

rather than:

```text
Customer
   ↓
Platform-controlled money account
   ↓
Platform holds money
   ↓
Platform settles cinema later
```

The latter changes the financial/legal architecture substantially.

CBK's current National Payment System framework regulates payment-service activity, while the **National Payment System Bill, 2026 currently listed by CBK is a draft bill**, so its provisions should not be treated as enacted law. ([Central Bank of Kenya](https://www.centralbank.go.ke/national-payments-system/ "National Payments System | CBK"))

The correct merchant/payment-service relationship should therefore be confirmed with Safaricom, the relevant PSP/acquirer, and legal/compliance advisers before production. (The status of the NPS Bill is time-sensitive, so re-check it before launch.)

**[Fixed] Platform fees conflict with this model.** §27, §28 and §41 describe a customer-facing "service fee" / "online booking fee". If the customer pays straight into the **cinema's** Paybill, the platform never touches that fee. It lands in the cinema's account. Pick one explicitly:

- **A. Fee belongs to the cinema** (the cinema sets it and keeps it). The platform bills the cinema separately through its SaaS subscription (§107). *Recommended for V1: keeps the platform out of the funds flow.*
- **B. Platform commission per ticket**, invoiced to the cinema periodically from the ledger (still no funds held).
- **C. Platform collects and settles.** This is the "platform holds money" model above, with the regulatory implications it describes. Avoid it.

---

# 32. M-Pesa payment state machine

Use explicit payment states:

```text
CREATED
   ↓
STK_REQUESTED        (Daraja accepted the push; we hold a CheckoutRequestID)
   ├── SUCCESS
   ├── FAILED
   ├── CANCELLED      (customer dismissed the prompt)
   ├── TIMEOUT        (no callback within the window)
   └── UNKNOWN        (callback missing/ambiguous)
```

**[Fixed]** `STK_REQUESTED` and `PENDING` meant the same thing and are merged. `TIMEOUT` and `UNKNOWN` are **not final**: a scheduled job resolves them with the Daraja STK/transaction status query before the hold is released (§24) or the payment is treated as failed. Refunds and reversals are recorded as ledger entries (§37), not as extra states on the payment.

Don't have:

```text
payment.status = "paid"
```

as soon as the frontend receives something saying success.

---

# 33. Never trust the browser for payment confirmation

Bad:

```text
Frontend:
"Payment succeeded!"

Backend:
"Great, issue ticket."
```

Correct:

```text
Frontend
   ↓
Backend creates payment
   ↓
Safaricom
   ↓
Safaricom callback
   ↓
Backend validates/correlates callback
   ↓
Backend checks transaction state
   ↓
Payment marked successful
   ↓
Booking committed
   ↓
Ticket generated
```

The client should merely display server state.

---

# 34. M-Pesa callback endpoint

The callback endpoint should be treated as an externally reachable integration endpoint.

```text
POST /webhooks/mpesa/{provider}
```

Controls:

- HTTPS only
- strict JSON/schema validation
- rate limiting
- request size limits
- correlation with the internal payment record
- idempotent processing
- never trust browser-supplied payment results
- verify shortcode/payment reference
- verify expected amount
- verify expected transaction identifiers
- verify customer/account reference where applicable
- use server-side transaction status checks/reconciliation where supported
- persist the raw provider response securely for audit/debugging, with PII minimisation
- acknowledge the provider quickly
- process business logic asynchronously
- retry failed processing
- dead-letter failed events

**[Jac] Implementation notes.**

- Jac's built-in webhook protocol (`@restspec(protocol=APIProtocol.WEBHOOK)`) requires the caller to send `X-API-Key` + an HMAC signature. **Daraja does not sign callbacks that way**, so it cannot be used for M-Pesa. The callback is a `def:pub` function with a custom `@restspec` path containing an **unguessable per-intent token** (e.g. `/hooks/mpesa/{intent_token}`). The token is set as the STK `CallBackURL` and is only a correlation aid. **The callback body is never trusted as proof of payment.** Success is only accepted after a server-side status query to Daraja confirms it, as the §33 flow requires.
- An anonymous `def:pub` call runs on the shared guest graph and **cannot write to the tenant's payment nodes** (they are not granted to the public). The callback therefore only **records a raw `CallbackReceipt` and schedules processing** (outbox/`on_commit`). A system-identity worker correlates, verifies and finalizes. This also meets "acknowledge quickly, process asynchronously" above.
- Allowlist Safaricom's published callback source IPs at the WAF/edge as an extra layer, not the only one.

---

# 35. Never let a webhook create a second ticket

Suppose Safaricom sends:

```text
callback 1
callback 2
callback 3
```

The system must result in:

```text
ONE payment
ONE booking
ONE ticket set
```

not:

```text
three payments
three tickets
```

Use:

```text
provider_transaction_id UNIQUE
```

and appropriate idempotency constraints.

**[Jac]** Jac's graph store has no declarative `UNIQUE` constraints. Uniqueness is enforced **structurally**, with a `ProviderTxnIndex` node per tenant holding a `provider_transaction_id → PaymentTransaction` edge, written through *find-or-create*. SERIALIZABLE + replay makes concurrent duplicate callbacks converge on one transaction (§25). Finalization is also guarded by state: only a payment in `STK_REQUESTED`/`UNKNOWN` can move to `SUCCESS`, so a second callback is a no-op.

---

# 36. M-Pesa reconciliation

A reconciliation subsystem is required.

Every day:

```text
M-Pesa transactions
       ↓
Internal payment ledger
       ↓
Match
       ↓
Matched / Missing / Duplicate / Amount mismatch / Unknown
```

Dashboard:

```text
Today's M-Pesa
KES 1,240,500

Internal sales
KES 1,240,500

Matched
KES 1,240,500

Exceptions
KES 0
```

Or:

```text
M-Pesa:          KES 1,250,000
Internal ledger: KES 1,245,000

Difference:      KES 5,000
```

Finance should immediately see it.

**[Fixed] Where the "M-Pesa transactions" side comes from must be designed, not assumed.** Daraja is built around per-transaction calls (STK, status query, C2B confirmation/validation URLs, account balance), not a general "list all transactions today" statement API. Realistic sources:

1. **C2B confirmation callbacks** registered on the cinema's shortcode (also catches customers who pay the Paybill directly, outside our STK flow).
2. **Transaction status queries** for every intent we initiated.
3. **Statement import** (CSV/Excel export from the M-Pesa org portal), uploaded by Finance or fetched by an approved integration.

Confirm the available options with Safaricom for each tenant's shortcode type (Paybill vs Till) during onboarding. **[Jac]** Daily reconciliation runs as a `@schedule(cron=...)` job. Cron is evaluated in **UTC**, so "end of business day in Nairobi" (EAT = UTC+3) must be converted explicitly.

---

# 37. Payments are a ledger, not merely a table

Financial transactions should be modeled as immutable events/ledger entries wherever possible.

Instead of editing:

```text
payment.amount = 0
```

record:

```text
ORIGINAL_PAYMENT
REFUND
REVERSAL
ADJUSTMENT
```

This makes audits and reconciliation much safer.

---

# 38. Refunds

Refunds need their own permissions.

```text
Customer requests refund
       ↓
Policy check
       ↓
Authorization
       ↓
Refund initiated
       ↓
Provider response
       ↓
Refund recorded
       ↓
Ticket invalidated
       ↓
Seats released
```

Potential rules:

```text
refundable until X hours before show
not refundable after show begins
partial refund
full refund
manual override
manager approval above KES X
```

Large refunds could require dual approval.

---

# 39. Don't store sensitive M-Pesa PIN information

The platform should **never receive or store an M-Pesa PIN**.

Payment authentication should happen through Safaricom's payment flow.

The system records the transaction outcome, not the customer's M-Pesa PIN.

---

# 40. PCI DSS

For a pure M-Pesa implementation, you do not suddenly become a card-processing environment merely because you accept digital payments.

But architect the system so adding cards later doesn't create unnecessary PCI scope.

If cards are introduced:

```text
Cinema storefront
       ↓
PCI-compliant payment provider
       ↓
Hosted checkout / redirect
```

is generally preferable to collecting raw card data yourself.

PCI SSC's current guidance emphasizes payment-page script integrity, authorization and tamper detection for e-commerce payment pages, and its updated SAQ A guidance distinguishes redirect/fully outsourced payment flows from embedded payment pages. ([PCI Perspectives](https://blog.pcisecuritystandards.org/new-information-supplement-payment-page-security-and-preventing-e-skimming "New Information Supplement: Payment Page Security and Preventing E-Skimming"))

---

# 41. Customer-facing cinema website

The generated cinema website should support:

### Home

```text
Cinema branding
Current films
Coming soon
Promotions
Featured movie
Location
Opening times
```

### Movie page

```text
Poster
Trailer
Synopsis
Genre
Runtime
Language
Age rating
Cast
Release date
Available formats
Available cinemas
```

### Showtime

```text
Movie
Date
Time
Auditorium
2D / 3D
Premium format
Ticket availability
```

### Seat selection

```text
Visual seat map
Seat types
Price
Available
Held
Sold
Accessible seats
```

### Checkout

```text
Booking summary
Customer details
Discount
Tax
Service fee
M-Pesa payment
```

### Ticket

```text
Movie
Date
Time
Venue
Auditorium
Seat
Ticket type
QR code
Booking reference
```

---

# 42. Customer self-service

A modern cinema platform should consider:

```text
order history
ticket retrieval
QR ticket
ticket resend
refund request
seat change
food ordering
add food to existing booking
loyalty points
membership
promotions
watchlist
favorite cinema
calendar integration
digital wallet
notifications
```

These are not arbitrary additions. Vista's current cinema platform, for example, integrates ticketing, food & beverage, loyalty, mobile ticket access, self-service, kiosks, seat-related services and reporting. ([vista.co](https://www.vista.co/lumos "Introducing Lumos"))

---

# 43. Concessions/F&B

I'd include this in the data model from the beginning even if the first release doesn't expose it.

```text
Product
Category
Price
Inventory
Modifier
Combo
Promotion
StockMovement
ConcessionOrder
ConcessionOrderItem
```

Support:

```text
Popcorn
Drinks
Combo deals
Meal packages
3D glasses
Merchandise
```

Later:

```text
Order online
Pay
Collect at counter
```

or:

```text
Pay
Choose seat
Deliver to seat
```

Vista currently offers seat-specific QR/RFID based food ordering and in-seat delivery concepts. ([Vista](https://www.vista.co/lumos "Introducing Lumos"))

---

# 44. Loyalty

A proper loyalty system should be ledger-based:

```text
LoyaltyAccount
    ↓
LoyaltyTransaction
    ├── EARN
    ├── REDEEM
    ├── EXPIRE
    ├── ADJUST
    └── BONUS
```

Potential:

```text
Bronze
Silver
Gold
VIP
```

But don't hardcode tiers.

Configure:

```text
points per KES
tier thresholds
expiry
eligible products
bonus campaigns
member pricing
birthday benefits
```

---

# 45. Promotions

The promotion engine will eventually become complicated.

Support:

```text
promo code
movie-specific discount
showtime-specific discount
seat-zone discount
customer-group discount
loyalty discount
buy X get Y
family discount
weekday discount
early-bird
student discount
bundle pricing
concession combo
```

Security requirements:

- server-side calculation
- rate limits
- single-use codes
- redemption limits
- tenant scoped
- expiration
- minimum purchase
- concurrency-safe redemption
- audit trail

Never trust:

```text
discountAmount = 500
```

from the browser.

---

# 46. QR ticket design

Do not put this into the QR:

```text
John Doe
0712345678
Movie XYZ
Seat A10
```

Prefer an opaque signed identifier such as:

```text
ticket_ref
random nonce
signature
```

Conceptually:

```text
QR
 ↓
TKT_8af821....
 ↓
Server
 ↓
Ticket status
 ↓
Does it belong to tenant?
 ↓
Is it for this show?
 ↓
Is it valid?
 ↓
Has it already been used?
 ↓
Redeem atomically
```

The QR should not itself be the authority.

**The server is the authority.**

---

# 47. Anti-replay protection for tickets

Once scanned:

```text
ticket.status = USED
used_at = ...
used_by = scanner_device
```

Second attempt:

```text
INVALID:
ALREADY_REDEEMED
```

Use an atomic operation so two scanners cannot redeem the same ticket simultaneously.

---

# 48. Scanner application

A separate scanner mode/application should be provided.

```text
Scanner Device
   ↓
Device authentication
   ↓
Tenant binding
   ↓
Showtime selected
   ↓
Scan QR
   ↓
Ticket validation
   ↓
Atomic redemption
```

Register each device:

```text
device_id
tenant_id
venue_id
auditorium_id
device_name
status
last_seen
certificate/token reference
```

Allow owner/admin to remotely:

```text
disable scanner
rotate credentials
view scanner activity
```

---

# 49. Offline scanning

Consider whether the venue's internet connection may fail.

There are two strategies.

### Online-first

```text
scan → server → response
```

Simpler and safer.

### Controlled offline mode

```text
server periodically signs ticket/show data
       ↓
scanner caches it
       ↓
offline scan
       ↓
local temporary redemption
       ↓
synchronization
```

Offline mode is significantly harder because two offline scanners could accept the same QR.

**Online verification should be the default**; offline mode should be treated as a deliberately designed future capability.

---

# 50. OWASP security baseline

As of 2026, the current OWASP Top 10 is **2025**, not 2021. Its categories include Broken Access Control, Security Misconfiguration, Software Supply Chain Failures, Cryptographic Failures, Injection, Insecure Design, Authentication Failures, Software/Data Integrity Failures, Security Logging/Alerting Failures, and Mishandling Exceptional Conditions. ([OWASP Top 10](https://top10.owasp.org/2025/en/ "OWASP Top 10:2025"))

The project security baseline should include:

```text
OWASP Top 10:2025
OWASP ASVS 5.0
OWASP API Security Top 10
OWASP Cheat Sheets
```

OWASP ASVS 5.0 specifically covers areas including authentication, session management, authorization, tokens, OAuth/OIDC, cryptography, communication, data protection, secure architecture, and security logging. ([Cornucopia](https://cornucopia.owasp.org/taxonomy/asvs-5.0 "asvs-5.0"))

---

# 51. API security

The OWASP API Security Top 10 is particularly relevant because this application will have a large API surface.

Important risks include:

```text
Broken Object Level Authorization
Broken Authentication
Broken Object Property Level Authorization
Unrestricted Resource Consumption
Broken Function Level Authorization
Unrestricted Sensitive Business Flows
SSRF
Security Misconfiguration
Improper API Inventory
Unsafe Consumption of APIs
```

OWASP specifically highlights object-level authorization: every API operation receiving an object identifier must ensure the caller can access that object. ([OWASP API Security Top 10](https://api-security.owasp.org/editions/2023/en/0x11-t10/ "OWASP Top 10 API Security Risks – 2023 - OWASP API Security Top 10"))

So:

```http
GET /bookings/123
```

must not simply mean:

```sql
SELECT * FROM bookings WHERE id = 123
```

It must mean:

```sql
SELECT ...
FROM bookings
WHERE id = 123
  AND tenant_id = current_tenant
```

and then authorization must still be checked.

**[Jac] equivalent.** There is no SQL `WHERE tenant_id`. The tenant filter is **the traversal path**:

```text
WRONG:  b = jobj(booking_id)                        # any tenant, grants ignored
RIGHT:  b = find booking_id among
            ctx.tenant → venue → screening → bookings (or a per-tenant index)
        if not found → 404 (don't reveal that it exists elsewhere)
        authorize(ctx, "bookings.read", b)
```

For customers, the boundary is ownership as well as tenancy: a customer may only reach bookings linked to *their* `CustomerProfile` in that tenant.

---

# 52. Security properties of API endpoints

Every endpoint should explicitly answer:

```text
Who is calling?
Which tenant?
What role?
What permission?
Which resource?
Which state?
Which business conditions?
```

For example:

```text
POST /admin/refunds/123
```

must validate:

```text
authenticated
+
tenant member
+
refund permission
+
booking belongs to tenant
+
ticket belongs to booking
+
refund policy allows it
+
payment is refundable
+
refund isn't already in progress
```

---

# 53. Business logic security

This is where cinema systems can get badly hurt.

Protect against:

### Double booking

```text
same seat + same showtime
```

### Free tickets

Manipulating:

```text
price = 0
```

### Discount abuse

Repeated promo redemption.

### Refund abuse

Refunding:

```text
same transaction multiple times
```

### Ticket reuse

Reusing screenshots.

### Showtime manipulation

Employee changing:

```text
price
show time
seat availability
```

without permission.

### Revenue manipulation

Deleting or changing completed sales.

Business logic security is explicitly part of modern application security guidance, including OWASP ASVS validation/business logic requirements. ([Cornucopia](https://cornucopia.owasp.org/taxonomy/asvs-5.0 "asvs-5.0"))

---

# 54. Input security

Every external input is untrusted:

```text
movie title
description
HTML
logo
poster URL
email
phone
coupon
seat ID
showtime ID
payment amount
domain
file
query
sorting
pagination
```

Use:

```text
allowlists
schema validation
length limits
type validation
range validation
parameterized queries
output encoding
HTML sanitization
```

---

# 55. Cinema CMS is an XSS risk

Cinema owners will need to customize:

```text
home page text
movie description
promotion
banner
footer
FAQ
terms
contact information
```

Do **not** let tenants inject arbitrary JavaScript.

Avoid something like:

```html
<script>
stealCustomerSession()
</script>
```

Tenant content should be:

```text
plain text
Markdown
strictly sanitized HTML
predefined content blocks
```

Not arbitrary JavaScript.

---

# 56. File upload security

Logo/poster uploads should have:

```text
MIME validation
file signature validation
maximum size
maximum image dimensions
image decoding limits
filename normalization
virus/malware scanning where appropriate
random storage key
non-executable object storage
```

Never use:

```text
/user_uploads/../../something
```

as a storage path.

Prefer:

```text
tenant/{tenant_id}/media/{random_uuid}.webp
```

**[Jac]** Use the ambient `store()` API (local disk in dev, `[scale.storage] type = "s3"` in prod, private bucket, served via `get_url(path, expires_in=…)` presigned URLs or a CDN in front). `UploadFile` buffers the whole body in memory, and the default body cap is 100 MB. Set `[serve.limits] max_body_bytes` to a few MB for the API, and have large media go directly to object storage with presigned uploads.

---

# 57. SSRF protection

The platform will eventually support:

```text
Movie poster URL
Trailer URL
Webhook URL
Custom integrations
```

Be extremely careful.

A malicious administrator/customer could provide:

```text
http://169.254.169.254/
```

or another internal resource.

Therefore:

```text
URL validation
DNS resolution checks
private IP blocking
redirect controls
protocol allowlist
egress filtering
response size limits
timeouts
```

This directly maps to OWASP API SSRF concerns. ([OWASP API Security Top 10](https://api-security.owasp.org/editions/2023/en/0x00-header/ "OWASP API Security Top 10"))

---

# 58. Rate limiting

Do not only rate-limit login.

Rate-limit:

```text
login
signup
password reset
OTP requests
seat hold
booking creation
payment initiation
promo redemption
ticket validation
QR scanning
API search
movie scraping/import
webhooks
admin export
```

Sensitive business flows deserve special protection because automated abuse can become an economic attack, not merely a technical one.

**[Jac] Where each limit lives.**

- **Edge (Cloudflare/WAF):** per-IP limits, bot management, and burst absorption for opening-night traffic. This is the first line.
- **Jac ingress / gateway:** `[scale.kubernetes] ingress_limit_rps` (per-IP) and `[scale.gateway.rate_limit]` for coarse per-route limits.
- **Application:** per-account / per-tenant business quotas (max held seats, promo attempts, OTP sends). **Do not implement these as a single counter node per tenant.** Under SERIALIZABLE every increment would conflict with every other (§25). Use per-customer counters or time-bucketed nodes, or keep hot counters at the edge.

---

# 59. Bot/scalping protection

Opening-day movie releases could generate huge traffic.

Protect:

```text
seat availability
seat holds
booking creation
promotion redemption
```

with:

```text
rate limits
per-IP quotas
per-account quotas
device fingerprinting where appropriate
bot detection
queueing
CAPTCHA/challenge only where justified
```

Do not make CAPTCHA mandatory for every customer action.

---

# 60. Caching security

Never cache tenant-private responses under generic keys.

Bad:

```text
/movie/123
```

when authorization or tenant context matters.

Better:

```text
tenant:{id}:movie:{id}
```

For public storefront content you can cache aggressively, but the tenant identity still needs to be derived from the hostname and server-side routing.

---

# 61. Security headers

Use at minimum an appropriately configured:

```text
Content-Security-Policy
Strict-Transport-Security
X-Content-Type-Options
Referrer-Policy
Permissions-Policy
```

and frame restrictions where applicable.

OWASP recommends secure HTTP header configurations including `X-Content-Type-Options` and an explicit referrer policy. ([OWASP Cheat Sheet Series](https://cheatsheetseries.owasp.org/cheatsheets/HTTP_Headers_Cheat_Sheet.html "HTTP Headers - OWASP Cheat Sheet Series"))

CSP needs special attention because you are hosting multiple cinema brands on the same platform.

---

# 62. CORS

Never:

```http
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true
```

for authenticated APIs.

Instead maintain an allowlist:

```text
https://cinemaA.yourplatform.com
https://cinemaB.yourplatform.com
https://customcinema.co.ke
```

and dynamically select the valid origin after domain verification.

**[Jac]** Single-process `jac run` hard-wires `allow_origins=['*']` with no config knob. Configurable CORS exists only on the **fleet gateway** (`[scale.gateway.cors]`, active under `--fleet` and every `jac scale deploy`), and it takes a static list. That cannot express "every verified tenant domain". Therefore:

- Serve storefront, admin and API **same-origin per hostname** (the Jac server serves the client bundle too), so browsers never need CORS for our own pages.
- Enforce the dynamic origin allowlist at the **edge proxy**, which already holds the verified-domain list (§8).
- Because auth uses a bearer token rather than cookies, `Access-Control-Allow-Credentials` is not required. The main CORS risk is reading responses cross-origin, which the edge policy blocks.

---

# 63. Encryption

### In transit

```text
HTTPS everywhere
TLS
secure internal service connections
```

### At rest

Encrypt:

```text
database
backups
object storage
logs where sensitive
secrets
```

Particularly sensitive fields can have application-level encryption:

```text
payment credentials
certain identity information
integration secrets
```

Keep encryption keys separate from encrypted data.

---

# 64. Key management

Use:

```text
KMS
HSM where appropriate
Vault
cloud secret manager
```

with:

```text
rotation
access policies
audit
revocation
separation of duties
```

Do not put:

```text
M-Pesa consumer key
M-Pesa consumer secret
database password
JWT signing private key
SMTP credential
```

in Git.

OWASP explicitly advises centralized secrets storage, controlled access, rotation, expiration and revocation. ([OWASP Cheat Sheet Series](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html "Secrets Management - OWASP Cheat Sheet Series"))

---

# 65. JWT/token security

If you use tokens:

```text
short lived
audience restricted
issuer validated
signature validated
algorithm allowlist
expiration checked
not accepted after logout where revocation is required
```

For machine-to-machine OAuth, use current OAuth security best practices; RFC 9700, published in January 2025, is the current OAuth 2.0 Security BCP. ([IETF Datatracker](https://datatracker.ietf.org/doc/html/rfc9700 "RFC 9700 - Best Current Practice for OAuth 2.0 Security"))

For customer/admin browser sessions, though, a secure server-side session cookie is often simpler.

---

# 66. Audit logging

This system needs **two kinds of logs**.

### Application logs

```text
request
response
latency
error
trace ID
```

### Security/audit logs

```text
user logged in
MFA enabled
employee invited
role changed
payment setting changed
refund initiated
refund approved
ticket voided
booking cancelled
tenant setting changed
domain changed
administrator created
scanner used
```

Audit records should include:

```text
timestamp
tenant_id
actor_id
action
resource_type
resource_id
source_ip
device/session
result
correlation_id
```

Do not log:

```text
password
session token
API secret
M-Pesa credential
full payment credential
```

---

# 67. Audit logs should not be editable by normal admins

For example:

```text
OWNER
    ↓
can see audit logs

OWNER
    X
cannot delete audit logs
```

Platform security administrators may have tightly controlled retention/archival controls.

---

# 68. Observability

Use:

```text
structured logs
metrics
distributed tracing
error tracking
health checks
synthetic monitoring
```

Metrics:

```text
requests/sec
5xx rate
latency
DB latency
queue depth
seat-hold rate
payment success rate
payment callback delay
booking conversion
failed payments
ticket scan failures
M-Pesa reconciliation mismatches
tenant resource consumption
```

---

# 69. Tenant-aware observability

Every important event should contain:

```text
tenant_id
```

For example:

```json
{
  "event": "payment_failed",
  "tenant_id": "...",
  "booking_id": "...",
  "provider": "mpesa",
  "correlation_id": "..."
}
```

This allows you to answer:

> "Is the whole platform broken, or is Cinema X having a payment problem?"

---

# 70. Noisy-neighbor protection

One cinema should not be able to consume the entire platform.

AWS highlights noisy-neighbor and blast-radius considerations in pooled SaaS architectures. ([AWS Documentation](https://docs.aws.amazon.com/whitepapers/latest/saas-tenant-isolation-strategies/pool-isolation.html "Pool isolation - SaaS Tenant Isolation Strategies: Isolating Resources in a Multi-Tenant Environment"))

Set tenant-specific:

```text
API rate
concurrent bookings
export limits
file storage
image upload size
queue limits
report generation limits
API quotas
```

Large tenants can later get dedicated resources.

---

# 71. Database design

Use:

```text
UUID/ULID
```

rather than predictable sequential public identifiers.

Internally you can still use database-specific IDs where appropriate, but external IDs should not make enumeration trivial.

OWASP authentication guidance also recommends randomly generated identifiers where exposed. ([OWASP Cheat Sheet Series](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html "Authentication - OWASP Cheat Sheet Series"))

---

# 72. Database constraints

Use the database to enforce invariants.

Examples:

```text
unique tenant domain
unique tenant membership
unique showtime seat booking
unique provider transaction ID
unique ticket QR reference
positive payment amount
valid seat type
valid ticket type
```

Don't depend purely on Jac/application validation.

**[Jac] Correction.** In a Jac deployment the database is the runtime's graph store, and **there is no way to declare SQL constraints** on archetype fields. Each invariant above is enforced with the Jac-native mechanism instead:

| Invariant | Mechanism |
| --- | --- |
| unique tenant domain | `DomainIndex` node on the platform graph, find-or-create under SERIALIZABLE |
| unique tenant membership | one `MemberOf` edge, checked-then-created in one transaction |
| unique showtime seat booking | one `SeatSlot` node per screening × seat with a state machine (§25) |
| unique provider transaction ID | `ProviderTxnIndex` (§35) |
| unique ticket QR reference | random 128-bit reference + index node |
| positive amount, valid seat/ticket type | typed `has` fields, `enum` types, and validation in the domain constructors |

Serializability comes from the transaction, and uniqueness comes from **modelling each unique thing as exactly one node**. The §112 test suite must include concurrency tests (parallel requests) for every row of this table.

---

# 73. Transaction boundaries

Critical transaction:

```text
reserve seats
+
create booking
```

should be atomic.

Payment finalization should have carefully defined transaction/state boundaries.

Use the **outbox pattern** for important domain events:

```text
DB transaction
    ↓
booking committed
    ↓
outbox event committed
    ↓
worker publishes
```

That prevents:

```text
DB succeeded
but event disappeared
```

**[Jac]** This comes built in. `on_commit(fn)` runs a side effect exactly once after the unit of work commits, and is discarded on abort or replay. An un-awaited cross-app walker spawn is written to the **outbox inside the caller's transaction** and delivered at-least-once, with backoff (8 attempts, then dead-letter) and an idempotency key. Consumers must still be idempotent.

---

# 74. Background jobs

Move expensive tasks out of the request path:

```text
email ticket
send SMS
generate PDF
generate reports
image processing
reconciliation
expire holds
send campaign
loyalty calculation
eTIMS synchronization
payment retry
```

Every job must contain:

```text
tenant_id
job_id
correlation_id
retry_count
```

and must be idempotent.

**[Jac]** Use `[scale.scheduler]`:

- `@schedule(trigger=ScheduleTrigger.STATIC, interval=… | cron=…)` for platform-wide sweeps (expire holds, resolve UNKNOWN payments, reconciliation). **Every replica fires its own copy of a static task**, so these jobs must be idempotent or be moved to dynamic jobs.
- `ScheduleTrigger.DYNAMIC` jobs (created via the `/jobs` API) take a **per-fire lease** when a database is configured, so they run once cluster-wide. Use them for per-tenant schedules (e.g. a tenant's reconciliation time).
- Scheduled tasks run as the **system identity**. Each job must load the tenant explicitly and verify `resource ∈ tenant` before acting (§128). The system identity can see everything, so this check is the only thing stopping a buggy job from acting across tenants.
- Cron is UTC. Convert from EAT.

---

# 75. Notification architecture

Support:

```text
Email
SMS
Push
WhatsApp later
```

Templates should be tenant-specific:

```text
cinema logo
brand colors
contact
refund policy
ticket details
```

But template customization must not allow arbitrary executable code.

---

# 76. Admin dashboard

The owner should see:

```text
Today's revenue
Tickets sold
Tickets scanned
Occupancy
Average ticket price
Top movies
Top showtimes
M-Pesa collections
Refunds
Concession sales
Outstanding reconciliation
```

Then drill down:

```text
Revenue
 ↓
Venue
 ↓
Auditorium
 ↓
Movie
 ↓
Showtime
 ↓
Ticket
```

---

# 77. Revenue reporting

Include:

```text
gross ticket revenue
discounts
tax
service fees
refunds
net revenue
concession revenue
M-Pesa collections
cash sales
online sales
POS sales
kiosk sales
```

Also useful cinema KPIs:

```text
occupancy %
tickets per show
revenue per available seat
average ticket price
concession spend per customer
showtime utilization
online sales %
repeat customer %
```

---

# 78. Financial separation

Don't make:

```text
booking.total_amount
```

the only financial record.

Separate:

```text
Order
Payment
PaymentTransaction
Refund
Settlement
TaxInvoice
LedgerEntry
```

This matters because:

```text
one order
→ multiple payments

one payment
→ partial refund

one booking
→ ticket + concessions

one M-Pesa transaction
→ reconciliation event
```

---

# 79. eTIMS

This is particularly important for Kenya.

KRA currently states that persons engaged in business are required to onboard eTIMS and issue electronic tax invoices. KRA also supports system-to-system integration and specialized integration options. ([Kenya Revenue Authority](https://www.kra.go.ke/online-services/etims "eTIMS - KRA"))

Therefore the platform should have an eTIMS-ready abstraction:

```text
TaxConfiguration
TaxInvoice
TaxInvoiceItem
TaxSync
TaxCreditNote
TaxDebitNote
```

Per tenant:

```text
KRA PIN
business name
VAT status
tax configuration
invoice configuration
eTIMS credentials/integration reference
```

And:

```text
sale
 ↓
invoice
 ↓
eTIMS integration
 ↓
KRA response
 ↓
invoice status
```

Don't assume every tenant has identical VAT/tax configuration.

---

# 80. Data protection in Kenya

Customers create personal data:

```text
name
email
phone
booking history
purchase history
preferences
loyalty data
potentially location/device information
```

Kenya's Data Protection Act and related regulations apply to personal-data processing, while the ODPC provides guidance on controller/processor roles, data protection impact assessments, retention and data subject rights. ([Odpc](https://www.odpc.go.ke/data-protection-laws-kenya/ "Data Protection Laws Kenya"))

The system should explicitly determine, **for each processing purpose**, whether:

```text
Cinema = data controller
Platform = data processor
```

or whether a particular activity creates a different relationship.

Do not assume the entire platform has one universal legal role.

---

# 81. Privacy by design

Collect only what you need.

For booking:

```text
email
phone
name
```

may be enough.

Don't automatically collect:

```text
national ID
date of birth
home address
gender
contacts
precise location
```

unless there is a documented reason.

Kenya's ODPC guidance emphasizes data minimization, safeguards and privacy by design/default. ([Odpc](https://www.odpc.go.ke/wp-content/uploads/2024/02/ODPC-Guidance-Note-on-Data-Protection-Impact-Assessment-1.pdf "ODPC-guidance-note-on-Data-Protection-Impact-assessment 1223"))

---

# 82. Data retention

Have a retention schedule.

For example:

```text
Authentication logs        → limited retention
Marketing events           → defined retention
Abandoned seat holds       → short retention
Customer profile           → until deletion/required retention
Financial transactions     → legally required retention
Tax invoices               → legally required retention
Security audit logs        → longer security retention
```

Kenya's Data Protection General Regulations require a retention schedule and deletion, anonymisation or pseudonymisation when the purpose/retention period ends, subject to applicable obligations. ([Odpc](https://www.odpc.go.ke/wp-content/uploads/2024/03/THE-DATA-PROTECTION-GENERAL-REGULATIONS-2021-1.pdf "SPECIAL ISSUE"))

---

# 83. Customer privacy controls

Customer portal:

```text
View personal data
Change personal data
Marketing preferences
Download relevant information
Request deletion where applicable
Request correction
Manage sessions
Log out all devices
```

ODPC lists data-subject rights including being informed, access, objection, correction and deletion of false/misleading data. ([Odpc](https://www.odpc.go.ke/rights-of-a-data-subject/ "Rights Of A Data Subject - Office of the Data Protection Commissioner (ODPC)"))

Deletion must, however, be designed around legal/financial retention requirements.

---

# 84. Breach response

A formal incident-response process is required:

```text
Detect
 ↓
Contain
 ↓
Investigate
 ↓
Assess impact
 ↓
Preserve evidence
 ↓
Notify appropriate parties
 ↓
Remediate
 ↓
Post-incident review
```

**[Fixed]** Kenya's Data Protection Act, 2019 (s.43) requires a data controller to notify the ODPC **within 72 hours of becoming aware** of a qualifying breach, and to notify affected data subjects without undue delay where there is a real risk of harm. A processor (the platform, for most tenant data; see §80) must notify the controller (the cinema) without delay. The incident system therefore needs a clock that starts at *discovery*, and the platform↔tenant agreement must fix who notifies whom. ([ODPC](https://www.odpc.go.ke/report-a-data-breach/ "Report a Data Breach - Office of the Data Protection Commissioner (ODPC)")) ([Odpc](https://www.odpc.go.ke/report-a-data-breach/ "Report a Data Breach - Office of the Data Protection Commissioner (ODPC)"))

---

# 85. DPIA

Because the system processes:

```text
large amounts of customer data
financial transaction information
behavioral/loyalty information
potentially children's data
```

a Data Protection Impact Assessment should be performed where required.

ODPC describes DPIAs as a mechanism for identifying and mitigating privacy risks and embedding safeguards before processing begins. ([Odpc](https://www.odpc.go.ke/wp-content/uploads/2024/02/ODPC-Guidance-Note-on-Data-Protection-Impact-Assessment-1.pdf "ODPC-guidance-note-on-Data-Protection-Impact-assessment 1223"))

---

# 86. Children's data

Cinemas naturally serve children.

Do not unnecessarily build customer profiles around:

```text
child's name
age
preferences
behavior
```

For a standard child ticket, an age category may be enough.

If you introduce child-specific accounts, loyalty, targeted marketing or profiling, get specific privacy/legal requirements assessed.

ODPC also publishes guidance relating to children's data. ([Odpc](https://www.odpc.go.ke/guidelines-2/ "Guidelines - Office of the Data Protection Commissioner (ODPC)"))

---

# 87. Cross-border data

If you run the platform on AWS/Azure/GCP regions outside Kenya, document:

```text
where data resides
what is transferred
why it is transferred
who receives it
what safeguards apply
which subprocessors are involved
```

ODPC's published framework addresses cross-border transfers and appropriate safeguards. ([Odpc](https://www.odpc.go.ke/rights-of-a-data-subject/ "Rights Of A Data Subject - Office of the Data Protection Commissioner (ODPC)"))

---

# 88. Security of third-party integrations

The platform will eventually integrate:

```text
Safaricom
eTIMS
email
SMS
analytics
movie metadata
payment providers
maps
loyalty
```

Treat all third parties as untrusted dependencies.

OWASP API Security explicitly includes unsafe consumption of APIs, and OWASP's 2025 Top 10 elevates software supply-chain failures as a major application-security category. ([OWASP API Security Top 10](https://api-security.owasp.org/editions/2023/en/0x00-header/ "OWASP API Security Top 10"))

Validate:

```text
TLS
timeouts
response size
schema
signature/authentication
rate limits
retries
idempotency
```

Never allow an external service's response to directly become trusted authorization data.

---

# 89. Software supply chain

The CI/CD pipeline should include:

```text
SAST
SCA
Secret scanning
Dependency vulnerability scanning
Container scanning
IaC scanning
SBOM generation
License checks
DAST
```

Pin critical dependencies.

Protect:

```text
main branch
release pipeline
production deployment credentials
CI secrets
artifact registry
```

The 2025 OWASP Top 10 explicitly lists **Software Supply Chain Failures** as A03. ([OWASP Top 10](https://top10.owasp.org/2025/en/ "OWASP Top 10:2025"))

---

# 90. Development environments

Have separate:

```text
Development
Testing
Staging
Production
```

Prefer separate cloud accounts/projects/subscriptions where practical.

Never:

```text
production DB
↓
developer laptop
```

for routine development.

Use synthetic data in development.

---

# 91. Database migrations

**[Jac] Rewritten.** The original section assumed per-tenant SQL schemas. With Jac:

- **Shared-deployment tenants all share one graph store**, so a code change migrates every tenant at once, and there is no per-tenant migration loop.
- Schema evolution is handled by the runtime. Added fields with defaults load automatically. Removed fields go to the **attic** (recoverable, never dropped). Type changes are coerced. Unloadable rows are **quarantined**, not deleted.
- **Renames must be declared**: `@archetype_alias("old.Name")` for archetype renames, and `schema_alias` / `schema_drop` / `schema_upgrade` inside `__jac_schema__` for field changes. An undeclared rename silently moves data to the attic.
- **Silo tenants** (dedicated deployments) get the same code release. The release pipeline rolls out to them in waves and checks each one (`jac db inspect`, `jac db quarantine list`).
- Operator runbook: `jac db inspect`, `jac db quarantine list`, `jac db alias add`, `jac db recover-all`.

Test every release that changes archetypes against:

```text
empty tenant
small tenant
large tenant
snapshot of production data from the previous release (anonymised)
```

and fail the release if any rows land in quarantine.

---

# 92. Tenant provisioning

Cinema signup should be a state machine.

```text
SIGNUP_STARTED
       ↓
EMAIL_VERIFIED
       ↓
TENANT_CREATED
       ↓
DOMAIN_CONFIGURED
       ↓
BRANDING_CONFIGURED
       ↓
VENUE_CONFIGURED
       ↓
SEAT_LAYOUT_CONFIGURED
       ↓
PAYMENT_CONFIGURED
       ↓
ADMIN_CONFIGURED
       ↓
READY_FOR_GO_LIVE
       ↓
ACTIVE
```

Never leave half-created tenants that have partial permissions.

**[Fixed]** This list, the signup flow in §134 and the checklist in §135 disagreed: MFA appeared only in §134, tax/eTIMS and test booking/payment/scan did not appear here, and "ADMIN_CONFIGURED" came after payment here but before website setup in §134. They are now reconciled like this:

- **Tenant state** (this section, a real state machine): `PROVISIONING → CONFIGURING → READY_FOR_GO_LIVE → ACTIVE`, plus `SUSPENDED / CLOSING / DELETED` (§93).
- **Onboarding steps** (§134) are a *checklist*, not a strict sequence. Branding, venue and pricing can be done in any order.
- **Go-live gate** (§135) is the single source of truth for moving to `ACTIVE`.
- `PROVISIONING` is atomic: the Tenant node, service principal, StaffGroup, owner membership and control-plane records are created in **one transaction**, so a half-created tenant cannot exist.

---

# 93. Tenant suspension

Support:

```text
ACTIVE
SUSPENDED
CLOSING
DELETED
```

A suspended cinema should:

```text
stop new bookings
stop new payments
disable admin access
retain required records
display appropriate storefront state
```

but not necessarily delete data.

**[Fixed]** "Disable admin access" is too blunt. A suspended cinema still has **customers holding valid tickets** and **legal/financial obligations**. While suspended:

- **Ticket scanning continues** for tickets already sold for screenings already scheduled (or those screenings are cancelled and refunded, as a deliberate decision).
- **Refunds and reconciliation remain possible**, through Finance/Owner roles, or through platform support if the suspension is for fraud.
- The owner keeps **read-only access to export their data and invoices**, unless the suspension reason legally prevents it.

---

# 94. Tenant deletion

Deletion should be deliberately difficult.

Require:

```text
owner authentication
MFA
confirmation
perhaps cooling-off period
```

Then:

```text
disable tenant
 ↓
stop traffic
 ↓
stop bookings
 ↓
archive financial records
 ↓
apply retention policy
 ↓
delete/anonymize eligible data
 ↓
remove DNS
 ↓
remove secrets
 ↓
remove storage
 ↓
remove caches
 ↓
remove search index
```

Remember the subdomain-takeover issue when removing DNS/resources. ([OWASP Cheat Sheet Series](https://cheatsheetseries.owasp.org/cheatsheets/Subdomain_Takeover_Prevention_Cheat_Sheet.html "Subdomain Takeover Prevention - OWASP Cheat Sheet Series"))

---

# 95. Backups

At minimum:

```text
automated database backups
point-in-time recovery
object-storage versioning
backup encryption
backup access controls
cross-region strategy where justified
```

And most importantly:

> **Test restores.**

A backup that has never been restored is only an assumption.

---

# 96. Disaster recovery

Define:

```text
RPO
RTO
```

For example, internally you might decide:

```text
Booking database:
RPO < 5 minutes
RTO < 1 hour
```

The numbers should come from business requirements, not arbitrary engineering preferences.

Use NIST CSF 2.0 as the broader security/risk framework: Govern, Identify, Protect, Detect, Respond and Recover. ([NIST](https://www.nist.gov/news-events/news/2024/02/nist-releases-version-20-landmark-cybersecurity-framework "NIST Releases Version 2.0 of Landmark Cybersecurity Framework | NIST"))

---

# 97. Availability architecture

For production:

```text
                    CDN / WAF
                        │
                 Load Balancer
                        │
              ┌─────────┴─────────┐
              │                   │
          Jac App 1           Jac App 2
              │                   │
              └─────────┬─────────┘
                        │
                 PostgreSQL
                 ┌──────┴──────┐
                 │             │
             Primary        Replica
                 │
              Backups

   Jac scheduler + outbox (in each app replica)
```

Stateless application servers make horizontal scaling simpler.

**[Jac]** Every Jac replica must point at the **same** `JAC_DB_URL` (k8s deploys inject it). The runtime reads and writes that one primary. It does not route reads to replicas, so the "Replica" box above is for **HA failover and reporting/analytics offload** (§100), not app read-scaling. Workers are the same Jac app (scheduler + outbox run in-process), not a separate codebase.

---

# 98. Performance

Cache:

```text
movie metadata
poster
public cinema configuration
seat layout
non-sensitive showtime data
```

Don't cache:

```text
customer private information
payment secrets
authorization decisions
fresh seat availability
```

CDN:

```text
movie posters
logos
static JS/CSS
public images
```

This dramatically reduces load during blockbuster releases.

---

# 99. Search

Eventually customers will want:

```text
Search movie
Search actor
Search genre
Search venue
Search showtime
```

If you introduce Elasticsearch/OpenSearch/etc., tenant filtering must be mandatory:

```text
tenant_id = current tenant
```

Never assume the search engine itself provides the security boundary.

---

# 100. Multi-tenant analytics

Analytics can be centralized:

```text
Platform Analytics
       │
       ├── Tenant A
       ├── Tenant B
       └── Tenant C
```

But the tenant administrator only gets:

```text
WHERE tenant_id = current_tenant
```

Both are required:

```text
operational analytics
```

and:

```text
platform-wide analytics
```

with different permissions.

---

# 101. Customer-facing SEO

Since each cinema receives a public website, include:

```text
SEO metadata
OpenGraph
structured data/schema.org
movie pages
cinema pages
location pages
sitemaps
robots.txt
canonical URLs
```

This becomes particularly valuable because every cinema effectively gets its own web presence.

---

# 102. Accessibility

Seat selection and ticketing should follow accessible web design.

Consider:

```text
keyboard navigation
screen readers
focus management
sufficient contrast
accessible labels
mobile accessibility
accessible seat identification
non-color-only state indicators
```

For seats, don't rely solely on:

```text
green = available
red = booked
yellow = held
```

Use textual/ARIA state as well.

---

# 103. Mobile-first design

Most customers will probably book from phones.

The booking flow should therefore be:

```text
Movie
 ↓
Date
 ↓
Showtime
 ↓
Seats
 ↓
Ticket type
 ↓
M-Pesa
 ↓
QR ticket
```

Don't make a customer navigate ten screens.

---

# 104. Admin UX

The admin portal should be operationally different from the public site.

Use:

```text
Dashboard
Venues
Screens
Seat layouts
Movies
Showtimes
Ticket pricing
Bookings
Customers
Concessions
Inventory
Promotions
Employees
Payments
Refunds
Reconciliation
Reports
Settings
Audit log
```

---

# 105. Employee management

Owner:

```text
Invite employee
 ↓
email
 ↓
role
 ↓
venue scope
 ↓
invitation
 ↓
employee accepts
 ↓
sets authentication
 ↓
MFA
 ↓
ACTIVE
```

Employee states:

```text
INVITED
ACTIVE
SUSPENDED
DISABLED
```

Don't delete employees with historical activity.

Their identity should remain attached to:

```text
refund
ticket void
booking cancellation
role change
cash adjustment
```

---

# 106. Employee separation of duties

Financial functions should not all belong to one role.

Example:

```text
Box Office
   → sell tickets

Finance
   → reconcile payments

Manager
   → approve refunds

Owner
   → configure payment account
```

For higher-risk cinemas you can support:

```text
request → approval → execution
```

rather than immediate execution.

---

# 107. Platform subscription billing

Separate:

```text
Cinema customer transactions
```

from:

```text
Cinema → platform SaaS subscription
```

These are different ledgers.

Don't mix:

```text
cinema ticket revenue
```

with:

```text
platform subscription revenue
```

---

# 108. API architecture

I'd separate API surfaces:

```text
/public
/customer
/admin
/scanner
/platform
/webhooks
```

Conceptually:

```text
GET /public/movies
GET /public/showtimes

GET /customer/bookings

POST /admin/showtimes
POST /admin/refunds

POST /scanner/tickets/{id}/redeem

GET /platform/tenants

POST /webhooks/mpesa
```

Each surface gets a distinct authorization policy.

**[Jac] Path corrections.** The Jac runtime already owns several route prefixes: `/admin` (the built-in **platform** admin portal and `PUT /admin/users/...`), `/user/*` (auth), `/walker/*`, `/function/*`, `/webhook/*`, `/jobs`, `/docs`, `/graph`, `/metrics`, `/health*`. Our tenant back-office **must not** use `/admin`. Use `/api/v1/{public|customer|staff|scanner|platform}/...` and `/hooks/mpesa/...` through `@restspec(path=...)`. In production set:

```toml
[serve]
docs_enabled  = false     # no /docs, /openapi.json
graph_enabled = false     # no /graph graph browser
```

and keep `/admin` reachable only from the platform operations network.

---

# 109. Webhooks need their own security model

A webhook is neither:

```text
anonymous user
```

nor:

```text
authenticated employee
```

It is:

```text
trusted external integration attempt
```

Therefore:

```text
schema validation
provider verification where available
correlation
idempotency
replay controls
rate limiting
logging
dead-letter handling
```

---

# 110. Rate limits should be tenant aware

For example:

```text
Public cinema:
100 requests/sec

Customer:
10 bookings/min

Employee:
higher administrative quota

Payment:
strict request quota

Scanner:
very low latency but high burst allowance
```

And platform-wide limits remain separate.

---

# 111. Security testing

Before production:

```text
unit tests
integration tests
end-to-end tests
authorization tests
tenant isolation tests
concurrency tests
payment tests
webhook tests
security tests
load tests
failure tests
backup restoration tests
```

The single most important multi-tenant security test suite should attempt:

```text
Tenant A → Tenant B
```

using:

```text
every API endpoint
every ID
every filter
every export
every report
every image
every object-storage key
every queue
every search query
every admin function
```

---

# 112. Automated tenant isolation testing

Create test users:

```text
Tenant A Owner
Tenant A Employee
Tenant A Customer

Tenant B Owner
Tenant B Employee
Tenant B Customer
```

Then generate tests such as:

```text
A customer requesting B booking → 403/404
A employee requesting B report → denied
A manager requesting B employee → denied
A booking from A referencing B seat → denied
A refund from A referencing B payment → denied
A media URL from B through A → denied
```

This should run on every deployment.

---

# 113. Security regression tests

Every security issue should eventually become:

```text
test case
```

For example:

```text
BUG-1023
Tenant A could see Tenant B's bookings.

Regression:
test_cross_tenant_booking_access()
```

That makes the fix permanent.

---

# 114. OWASP ASVS as the project security checklist

Instead of inventing a random security checklist, map implementation against ASVS.

The project security matrix can contain:

```text
ASVS 01 Encoding/Sanitization       → requirement
ASVS 02 Validation/Business Logic   → requirement
ASVS 03 Frontend Security           → requirement
ASVS 04 API                         → requirement
ASVS 05 File Handling               → requirement
ASVS 06 Authentication              → requirement
ASVS 07 Session                     → requirement
ASVS 08 Authorization               → requirement
ASVS 09 Tokens                      → requirement
ASVS 10 OAuth/OIDC                  → requirement
ASVS 11 Cryptography                → requirement
ASVS 12 Communication               → requirement
ASVS 13 Configuration               → requirement
ASVS 14 Data Protection             → requirement
ASVS 15 Architecture                → requirement
ASVS 16 Logging                     → requirement
```

OWASP's current ASVS 5.0 taxonomy explicitly organizes controls this way. ([Cornucopia](https://cornucopia.owasp.org/taxonomy/asvs-5.0 "asvs-5.0"))

---

# 115. NIST CSF for operational security

Use:

```text
GOVERN
IDENTIFY
PROTECT
DETECT
RESPOND
RECOVER
```

rather than thinking security ends at:

```text
"we encrypted the database"
```

NIST CSF 2.0 explicitly added **Govern** to the existing Identify, Protect, Detect, Respond and Recover functions. ([NIST](https://www.nist.gov/news-events/news/2024/02/nist-releases-version-20-landmark-cybersecurity-framework "NIST Releases Version 2.0 of Landmark Cybersecurity Framework | NIST"))

---

# 116. Important cinema-specific features the system should add

Beyond the initial requirements:

### Operations

```text
multiple venues
multiple screens
seat layout editor
seat zones
screen types
2D/3D/premium formats
show scheduling
ticket classes
pricing rules
accessible seating
house seats
blocked seats
```

### Customer

```text
movie discovery
trailers
search
watchlist
favorites
digital tickets
QR
refunds
seat changes
loyalty
promos
concessions
gift cards
membership
notifications
```

### Cinema revenue

```text
ticket sales
concessions
inventory
discounts
refunds
M-Pesa reconciliation
tax invoices
daily settlement
financial reports
```

### Front-of-house & staff operations

```text
box-office POS
kiosk
scanner
staff management
cash management
shift management
device management
audit
```

### Marketing

```text
promotions
coupon engine
loyalty
customer segmentation
campaigns
push/email/SMS
```

Vista's current cinema products demonstrate the industry's movement toward combining ticketing, F&B, loyalty, kiosks, customer self-service, centralized CMS and analytics rather than treating ticketing as an isolated function. ([vista.co](https://www.vista.co/lumos "Introducing Lumos"))

Qube also demonstrates the importance of theatre-level occupancy validation and centralized auditing in cinema operations. ([qubecinema.com](https://www.qubecinema.com/products/icount "Products | ICOUNT | Qube"))

---

# 117. A particularly useful future feature: seat-specific concessions

Imagine:

```text
Customer books:
Screen 4
Seat B12

Before movie:
"Add food"

Popcorn
Coke
Chicken wings
Combo

↓

Pay

↓

Deliver to seat B12
```

This links:

```text
Ticket
+
Seat
+
Concession order
+
Customer
```

which can become a significant part of the system later. Vista already exposes seat-associated F&B ordering concepts. ([Vista](https://www.vista.co/lumos "Introducing Lumos"))

---

# 118. Gift cards

Another useful cinema domain:

```text
GiftCard
GiftCardTransaction
```

with:

```text
issue
redeem
partial redemption
expire
refund
transfer
```

Gift-card balances need the same financial-ledger discipline as payments.

---

# 119. Private screenings/events

Cinemas may later sell:

```text
private screening
corporate event
birthday screening
school booking
premiere
conference
```

So don't make the booking engine depend entirely on:

```text
Movie + Showtime
```

A more extensible model is:

```text
Screening
```

with:

```text
MovieScreening
PrivateEventScreening
SpecialEventScreening
```

The ticketing engine can then operate across them.

**[Fixed]** The draft called this abstraction `Session`, which clashes with authentication sessions (§9, §13), and kept using `Showtime` elsewhere. The document now uses **`Screening`** as the bookable unit throughout. "Showtime" survives only as a UI word.

---

# 120. Showtime scheduling

Administrators should be able to:

```text
create show
duplicate show
bulk schedule
cancel
reschedule
publish
unpublish
close booking
```

But prevent:

```text
same auditorium
overlapping showtimes
```

unless explicitly configured.

---

# 121. Show lifecycle

I'd define:

```text
DRAFT
  ↓
SCHEDULED
  ↓
PUBLISHED
  ↓
ON_SALE
  ↓
SALES_CLOSED
  ↓
STARTED
  ↓
COMPLETED
```

Alternative exceptional state:

```text
CANCELLED
```

This prevents nonsense such as:

```text
customer buying tickets for a completed show
```

**[Fixed]** `SCHEDULED` and `PUBLISHED` are separate states: a screening can be scheduled internally (for planning or overlap checks) before it is visible, and publishing is what creates the public storefront projection (§4) and the `SeatSlot` inventory.

---

# 122. Ticket lifecycle

```text
ISSUED
    ↓
USED
```

Alternative:

```text
ISSUED → VOIDED     (staff action, reason required)
ISSUED → REFUNDED   (via refund flow, §38)
ISSUED → EXPIRED    (screening completed without scan)
```

**[Fixed]** The draft gave tickets `RESERVED` and `PAID` states, which duplicate the SeatSlot hold (§24) and the Payment state (§32). A **ticket only exists once the booking is CONFIRMED** (payment verified). Before that, only the hold and the payment exist.

Never delete a ticket just because it is invalid.

Its history matters.

---

# 123. Booking lifecycle

```text
HELD
   ↓
PAYMENT_PENDING
   ↓
CONFIRMED          (payment verified; SeatSlots SOLD and tickets ISSUED in the same transaction)
   ↓
COMPLETED          (screening finished)
```

Failure / exception:

```text
HELD → EXPIRED
PAYMENT_PENDING → FAILED
CONFIRMED → CANCELLED | REFUNDED | PARTIALLY_REFUNDED
PAYMENT_PENDING → NEEDS_ATTENTION   (late success after seats were released, §24)
```

**[Fixed]** `DRAFT` was dropped: a booking without held seats is just UI state. `TICKET_ISSUED` was also dropped: issuing tickets is part of confirmation, so a separate state would reintroduce the §124 crash window it was meant to describe.

---

# 124. M-Pesa + booking consistency problem

This is a critical edge case:

```text
Seats reserved
      ↓
M-Pesa succeeds
      ↓
The server crashes
      ↓
Ticket wasn't created
```

A recovery worker is required to find:

```text
PAYMENT_SUCCESS
+
BOOKING_NOT_FINALIZED
```

and repair it.

Likewise:

```text
Ticket generated
+
payment uncertain
```

must be reconciled before treating it as paid.

This is why payment, booking and ticketing should use explicit state machines rather than boolean fields.

**[Jac]** On Jac the window is smaller but not gone. Payment `SUCCESS`, booking `CONFIRMED`, SeatSlots `SOLD` and ticket issuance happen in **one serializable unit of work** (§123), so a crash leaves either all of them or none. The crash window that remains sits *between* Safaricom taking the money and our finalization committing (callback lost, worker crashed, conflict retries exhausted). The recovery job is a `@schedule` sweep that finds `PaymentIntent` in `STK_REQUESTED/UNKNOWN` older than N minutes, queries Daraja, and finalizes or releases. Emails/SMS for the ticket are sent through `on_commit`, so they never go out for a rolled-back confirmation.

---

# 125. Event-driven architecture

Eventually useful events:

```text
TenantCreated
TenantActivated

EmployeeInvited
EmployeeRoleChanged

MoviePublished
ShowtimePublished

SeatHeld
SeatHoldExpired
BookingCreated
BookingConfirmed
BookingCancelled

PaymentInitiated
PaymentSucceeded
PaymentFailed
PaymentRefunded

TicketIssued
TicketScanned
TicketVoided

ConcessionOrdered
LoyaltyPointsEarned
LoyaltyPointsRedeemed
```

Every event carries:

```text
event_id
tenant_id
occurred_at
actor_id
correlation_id
event_type
payload
version
```

---

# 126. Jac-specific architecture

Because the system is built in **Jac**, the language itself should not become the security boundary.

Think:

```text
HTTP/API layer
       ↓
Authentication
       ↓
Tenant Context
       ↓
Authorization Policy
       ↓
Domain Walker/Ability
       ↓
Repository
       ↓
Tenant-specific persistence
```

A walker should never simply do:

```text
read booking
```

without having an established:

```text
AuthContext
TenantContext
```

Conceptually:

```text
AuthContext
{
    user_id
    tenant_id
    role_ids
    permission_set
    session_id
}
```

Then every protected domain operation receives that context.

**[Jac] Concretely:**

- The JWT gives us the **caller's root** implicitly. There is no `user_id` parameter to trust or forge. `TenantContext` is built *server-side* from `root -[MemberOf]-> StaffGroup -> Tenant` (staff) or `root -> CustomerProfile(tenant)` (customers).
- The "Repository" layer is **traversal from the Tenant node**. Domain functions take `ctx: TenantContext` as their first parameter, and the only way to get a `TenantContext` is `_resolve_tenant_context(selector)`, a private (`_`-prefixed, off the API) helper.
- Endpoint visibility: **every tenant/customer endpoint is authenticated** (plain `def` / `walker`). `def:pub` is reserved for the public storefront projection and the M-Pesa callback. A `def:pub` endpoint that writes user data puts it on the shared guest graph. That is a silent data leak, not an error.
- **Guest checkout** (booking without an account, §11): an anonymous caller has no root of their own, so the server must create the Booking **inside the tenant subgraph** (owned by the tenant principal, via a system-side write) and return a random booking reference + secret for later retrieval. Whether a `def:pub` call can write into a tenant-owned subgraph under the runtime's permission model is a spike (§138). Until that is proven, V1 requires a lightweight customer account (phone/email + OTP).

---

# 127. Don't use global mutable tenant state

Avoid designs equivalent to:

```text
current_tenant = ...
```

in a global process variable.

Because concurrent requests could potentially leak tenant state.

Prefer request-scoped context:

```text
request
 → authenticated context
 → tenant context
 → domain operation
```

This is especially important in a multi-user server.

**[Jac]** In Jac this means **never store tenant/user state in a `glob`**. Module globals are per-process and shared across concurrent requests and workers. The same goes for caches keyed without a tenant. Pass `TenantContext` explicitly.

---

# 128. Jac walkers and workers

Background walkers should explicitly contain tenant context:

```text
{
    tenant_id,
    booking_id,
    operation
}
```

rather than assuming:

```text
some global cinema
```

For example:

```text
expire_seat_hold(
    tenant_id,
    showtime_id,
    hold_id
)
```

The worker must verify that:

```text
hold.tenant_id == tenant_id
```

before modifying it.

---

# 129. Central authorization policy

Don't implement:

```text
if user.role == "manager":
```

in 500 different walkers.

Build a consistent authorization layer:

```text
authorize(
    actor,
    action,
    resource,
    context
)
```

Conceptually:

```text
authorize(
    user,
    "refund",
    payment,
    tenant
)
```

This makes it much harder for an endpoint to accidentally bypass the authorization policy.

**[Jac]** Two layers, deliberately:

1. **Graph grants** (`allow_group` per tenant StaffGroup) enforce the **tenant boundary** in the runtime itself. Even a buggy endpoint cannot read another tenant's nodes through normal traversal.
2. **`authorize(ctx, action, resource)`** enforces **role, venue scope and business rules** (e.g. an usher can read a ticket but not refund it). Grants cannot express these, because every staff member of a tenant holds the same graph-level access.

`authorize` re-reads the membership and role from the graph on every call (§13), so revoking a role takes effect immediately despite long-lived JWTs.

AWS's multi-tenant authorization guidance similarly emphasizes consistent, pervasive authorization rather than duplicating ad-hoc authorization logic across APIs. ([AWS Documentation](https://docs.aws.amazon.com/prescriptive-guidance/latest/saas-multitenant-api-access-authorization/introduction.html "Multi-tenant SaaS authorization and API access control: Implementation options and best practices - AWS Prescriptive Guidance"))

---

# 130. The four security boundaries

For this application, the following four security boundaries should be explicitly documented:

```text
1. Platform boundary
   Platform Admin → all tenants

2. Tenant boundary
   Tenant A → never Tenant B

3. Role boundary
   Permission sets per role, scoped to tenant / venue / auditorium
   (NOT a linear ladder: Finance can refund but not manage staff;
    Admin can manage staff but need not see revenue; §14, §106)

4. Customer/resource boundary
   Customer A → only their own bookings/tickets
```

This should become a formal security model.

---

# 131. Threat model

Before coding, create threats for:

```text
Tenant A accesses Tenant B
Customer modifies ticket price
Customer selects already-sold seat
Customer reuses QR
Employee refunds another transaction
Employee changes M-Pesa configuration
Attacker takes over cinema subdomain
Attacker steals admin session
Attacker uploads malicious image
Attacker injects JavaScript into cinema CMS
Attacker floods seat API
Attacker replays payment webhook
Attacker spoofs payment callback
Attacker obtains forgotten domain
Attacker enumerates booking IDs
Attacker accesses another tenant's object-storage files
Attacker abuses promotion
Attacker exports customer database
Attacker steals M-Pesa credentials
```

This becomes the security backlog.

---

# 132. Reference implementation architecture

For **V1**, my concrete stack architecture would be:

```text
                    Cloudflare / WAF / CDN
                             │
                ┌────────────┴────────────┐
                │                         │
        Customer Storefront          Admin Portal
                │                         │
                └────────────┬────────────┘
                             │
                         Jac API
                             │
             ┌───────────────┼─────────────────┐
             │               │                 │
          Auth/AuthZ      Cinema Domain     Payment
             │               │                 │
             └───────────────┼─────────────────┘
                             │
                       PostgreSQL
                             │
               ┌─────────────┴─────────────┐
               │                           │
          Control Plane                Tenant schemas
                                             │
                                    tenant_A / tenant_B
                                             │
                                     Booking/Ticketing
```

**[Jac]** "Tenant schemas" above should read **"tenant subgraphs"** (§4). There is one Jac graph store in PostgreSQL, and each tenant's data is a subgraph owned by its service principal.

Alongside:

```text
Jac scheduler + outbox (in-process workers)
Redis (optional, later: cache only)
Object Storage
Secrets Manager
KMS
Email/SMS provider
Safaricom Daraja
eTIMS integration
Monitoring
Centralized Logs
```

---

# 133. Recommended tenancy strategy

For this cinema SaaS, the tenancy strategy is:

### Control plane

```text
shared database
```

### Cinema operational data

```text
tenant subgraph in the shared Jac graph store,
owned by a per-tenant service principal, staff via group grants   [Jac, §4]
```

### Extremely sensitive/large tenants

```text
dedicated Jac deployment (own JAC_DB_URL), same code
```

### Object storage

```text
tenant-specific prefix/bucket policy
```

### Cache

```text
tenant-prefixed keys (if/when a cache is introduced)
```

### Queue

```text
tenant-aware outbox/scheduler payloads (Jac built-ins)
```

### Search

```text
tenant namespace/filter
```

### Payments

```text
tenant-specific credentials in Secrets Manager/Vault
```

### Authentication

```text
central identity
+
tenant membership
```

That is essentially a **bridge model**: shared SaaS control plane and application infrastructure with stronger isolation applied to tenant-specific resources. AWS explicitly describes this type of hybrid isolation as the bridge model. ([AWS Documentation](https://docs.aws.amazon.com/whitepapers/latest/saas-tenant-isolation-strategies/the-bridge-model.html "The bridge model - SaaS Tenant Isolation Strategies: Isolating Resources in a Multi-Tenant Environment"))

---

# 134. Refinement of the tenant owner identity model

The signup flow should be:

```text
                CINEMA OWNER
                     │
                 Sign Up
                     │
              Verify Email
                     │
              Enable MFA
                     │
              Create Tenant
                     │
           Enter business details
                     │
             Choose subdomain
                     │
                 Add logo
                     │
               Create venue
                     │
           Design seat layout
                     │
             Configure pricing
                     │
         Connect/verify M-Pesa
                     │
           Configure tax/eTIMS
                     │
          Invite administrators
                     │
             Configure website
                     │
              Add first movie
                     │
             Add first show
                     │
              TEST BOOKING
                     │
              TEST PAYMENT
                     │
              TEST QR SCAN
                     │
                 GO LIVE
```

That last part is important.

**Don't allow a tenant to become fully active simply because signup completed.**

The system should run a go-live checklist.

---

# 135. Go-live checklist

Before activation:

```text
✓ Owner email verified
✓ Owner MFA enabled
✓ Cinema business profile complete
✓ Platform subdomain live (custom domain: verified + TLS only if one is configured)
✓ Branding set (logo optional)
✓ Venue configured
✓ Screen configured
✓ Seat layout published
✓ Pricing configured
✓ M-Pesa verified
✓ Payment test successful
✓ Callback verified
✓ Reconciliation configured
✓ Admin users configured
✓ Roles reviewed
✓ Privacy policy added
✓ Terms/refund policy added
✓ eTIMS configuration reviewed
✓ Test booking successful
✓ Test QR scan successful
```

Then:

```text
TENANT = ACTIVE
```

---

# 136. Non-negotiable security requirements

The implementation's **non-negotiable** security areas are:

```text
Tenant isolation
RBAC/ABAC authorization
MFA for privileged users
Secure sessions
No cross-tenant IDs
Server-side price calculation
Concurrency-safe seat reservation
Idempotent payments
M-Pesa callback validation
M-Pesa reconciliation
Secrets manager
Immutable/auditable financial history
QR anti-replay
Audit logs
Rate limiting
WAF/CDN
Input validation
XSS/SSRF protection
Secure file uploads
Backups + tested restoration
Data retention/privacy controls
eTIMS readiness
Security testing
Tenant-isolation regression tests
Incident response
```

---

# 137. Standards baseline for project documentation

The project documentation should contain a `/docs/security/` section with:

```text
security-architecture.md
tenant-isolation.md
authentication.md
authorization.md
payment-security.md
mpesa-integration.md
data-protection.md
privacy.md
incident-response.md
backup-disaster-recovery.md
secure-development.md
api-security.md
threat-model.md
audit-logging.md
```

And explicitly map the project to:

```text
OWASP Top 10:2025
OWASP ASVS 5.0
OWASP API Security Top 10
OWASP Cheat Sheets
NIST CSF 2.0
OAuth 2.0 Security BCP / RFC 9700
Kenya Data Protection Act + ODPC guidance
PCI DSS 4.0.1 where card processing becomes relevant
KRA eTIMS requirements
Safaricom Daraja documentation
CBK payment-system requirements
```

The official sources support that standards combination: OWASP's current Top 10 is 2025, ASVS 5.0 covers the application-security control areas, OWASP has a dedicated API Top 10, and NIST CSF 2.0 provides the broader governance/detection/recovery framework. ([OWASP Top 10](https://top10.owasp.org/2025/en/ "OWASP Top 10:2025"))

---

## Reference architecture

In one picture:

```text
                       ┌───────────────────────┐
                       │   PLATFORM CONTROL    │
                       │                       │
                       │ tenants               │
                       │ users                 │
                       │ memberships           │
                       │ domains               │
                       │ subscriptions         │
                       │ provisioning          │
                       └───────────┬───────────┘
                                   │
                     ┌─────────────┴─────────────┐
                     │                           │
              PUBLIC STOREFRONT             ADMIN PORTAL
                     │                           │
                     └─────────────┬─────────────┘
                                   │
                            ┌──────▼──────┐
                            │  JAC API    │
                            │             │
                            │ AuthN       │
                            │ AuthZ       │
                            │ Tenant      │
                            │ Cinema      │
                            │ Booking     │
                            │ Ticketing   │
                            │ Payments    │
                            └──────┬──────┘
                                   │
            ┌──────────────────────┼──────────────────────┐
            │                      │                      │
      ┌─────▼──────┐        ┌──────▼─────┐        ┌──────▼──────┐
      │ PostgreSQL │        │ Jac        │        │ Object      │
      │ (Jac graph │        │ scheduler  │        │ Storage     │
      │  store)    │        │ + outbox   │        │             │
      │ control +  │        │ (in-app)   │        │ tenant media│
      │ tenant     │        │            │        │             │
      │ subgraphs  │        │            │        │             │
      └────────────┘        └────────────┘        └─────────────┘
                                   │
                              ┌────▼─────┐
                              │ Workers  │
                              └────┬─────┘
                                   │
            ┌──────────────────────┼──────────────────────┐
            │                      │                      │
       ┌────▼────┐            ┌────▼────┐            ┌────▼────┐
       │ Daraja  │            │ eTIMS   │            │ Email/  │
       │ M-Pesa  │            │ KRA     │            │ SMS     │
       └─────────┘            └─────────┘            └─────────┘

                     SECURITY AROUND EVERYTHING:
       WAF + TLS + MFA + Secrets + KMS + Audit + SIEM
       Rate Limits + Backups + Monitoring + Isolation Tests
```

The most important design choice is therefore **not Jac syntax, not the UI, and not even the M-Pesa API**.

It is establishing an unbroken chain:

```text
HOSTNAME (selector, resolved at the edge)
   ↓
TENANT
   ↓
USER (JWT → caller root)
   ↓
MEMBERSHIP
   ↓
ROLE/PERMISSION
   ↓
RESOURCE
   ↓
DATABASE
```

and making sure that **every single request, background job, cache lookup, file access, payment operation, report, search query and QR scan follows that chain**.

This is the foundation for the Jac implementation.

---

# 138. Jac platform constraints and required spikes **[Jac]**

This section collects the places where the design depends on runtime behaviour that the docs don't fully pin down. **Each item is a short proof-of-concept (spike) to run before building the dependent feature.** They are ordered by how much of the design rests on them.

| # | Question | Why it matters | Fallback if the answer is "no" |
| --- | --- | --- | --- |
| S1 | Can a server-side flow create a **per-tenant service principal** and create nodes owned by it, while running on behalf of the signed-up owner? | §4 ownership model | All tenant data owned by the platform system identity; tenant boundary enforced by `authorize()` + group grants only (weaker; see §5 table) |
| S2 | Do `allow_group` grants on tenant nodes let staff (via `MemberOf` → StaffGroup) **read and write** through normal traversal, and does revoking membership immediately remove access? | §4 layer 1, §13 revocation | Per-root `allow_root` grants (O(N staff) per node) or system-identity access behind `authorize()` |
| S3 | Can `_before_request` middleware pass a resolved value (tenant slug from `Host`/proxy header) to the endpoint, or reject the request? | §7 hostname resolution | Client passes the slug as a parameter (acceptable under selector-vs-authority) |
| S4 | Can an anonymous `def:pub` request (M-Pesa callback, guest checkout) write a record that a system-identity worker can later process? | §34, §126 guest checkout | Callback writes to `root.shared` inbox node with `__jac_access__` restricted; guest checkout deferred |
| S5 | Behaviour of SERIALIZABLE + replay under **opening-night load** on SeatSlots (hundreds of concurrent holds on one screening) | §25 | Tune `conflict_max_attempts`; add an edge queue/waiting room (§59) |
| S6 | Can staff JWT lifetime be set below 1 day, and can the Jac client keep the token out of `localStorage`? | §13 | External IdP for staff; aggressive CSP; server-side membership re-check on every call (already required) |
| S7 | Are the anonymous storefront reads of the `root.shared` projection fast enough with `[scale.database] indexes` on the filtered fields? | §4 public catalogue, §98 | CDN caching of storefront responses keyed by tenant |
| S8 | What password hashing and reset-token behaviour does the built-in `/user/*` auth use (Argon2id? non-enumerating reset?) | §12 | Wrap/replace reset endpoints; external IdP |

**Production config baseline (non-negotiable):**

```toml
[serve]
docs_enabled  = false
graph_enabled = false

[serve.auth]
# secret: set via the JAC_SERVE_AUTH_SECRET env var from the secrets manager,
# never committed and never the shipped placeholder

[serve.proxy]
trusted = ["<edge proxy CIDRs only>"]

[serve.limits]
max_body_bytes = 5242880              # 5 MB; media goes direct to object storage

[scale.storage]
type = "s3"                           # private bucket, presigned URLs
bucket = "<platform-media-bucket>"    # keys: tenant/{tenant_id}/media/{uuid}.webp
```
