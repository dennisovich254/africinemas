# AfriCinemas — Implementation Plan

> **Status:** Draft v1 (2026-09-26), awaiting approval
> **Timebox:** 4-week Jac hackathon
> **Architecture reference:** `resources/cinema-saas-architecture.md` ("§n" below means a section of that document)
> **Stack:** Jac 0.37.x (pinned), one shared deployment, Postgres (Jac graph store), Gemini via `by llm`, M-Pesa Daraja (sandbox)

---

## 1. Context

AfriCinemas is a multi-tenant cinema SaaS. A cinema owner signs up, configures venues, screens, seat layouts, movies and screenings, and gets a public storefront. Customers pick seats and pay with M-Pesa, then receive QR tickets that ushers scan at the door. Owners see revenue and occupancy, and AI features help both owners and customers.

The product ships as **one Jac workspace with three clients over one server**:

| Client | Jac kind | UI tech | Purpose |
| --- | --- | --- | --- |
| `web` | `web-app` | React DOM (jac-shadcn) | The server, the public storefront, and the full owner/staff back-office |
| `desktop` | `desktop` | Same React DOM bundle in an OS webview | Counter / box office / admin station. `backend = <server URL>`, so there is **no embedded DB** |
| `mobile` | `mobile` | Native React Native screens (`@jac/mobui`) | Customer booking and tickets, usher QR scanner (camera), box-office quick sale, owner summary |

Desktop reuses the web UI unchanged. Mobile needs its own screens (mobUI rejects HTML), but **all business logic and API wrappers live in shared modules**, so the mobile app is a thin view layer.

### 1.1 Responsive web: phone and PC are both first-class

Most customers will book on a phone, in a mobile browser, without installing the app. So the **web app itself must be fully usable at phone width**. The native mobile app is an extra, not the only mobile experience.

| Surface | Primary device | Approach |
| --- | --- | --- |
| Public storefront (browse, seat map, checkout, tickets) | **Phone** | **Mobile-first.** Designed at 375 px first, then enhanced for tablet/PC. Sticky bottom action bar (selected seats, total, "Pay with M-Pesa"). Tap targets ≥ 44 px. Pinch/zoom + pan on the seat map. Single-column checkout. Tickets readable offline once loaded. |
| Staff tools (scanner, box-office sale) | Phone / tablet | Mobile-first, one-hand use, large buttons. |
| Back-office (dashboard, movies, screenings, staff, settings) | **PC** | Desktop-first, but **fully responsive**: the sidebar collapses to a drawer and wide tables become cards. Owners can check the dashboard and approve things on a phone. |
| Seat layout designer | PC | Needs a wide screen. Below 768 px it shows a read-only preview with a clear "Use a larger screen to edit layouts" message, not a broken editor. |

Breakpoints (Tailwind defaults, used everywhere): **base = phone (≥ 360 px)**, `sm` 640, `md` 768 (tablet), `lg` 1024 (laptop), `xl` 1280 (desktop). No horizontal page scroll at any width, and no hover-only interactions.

Optional (decided at 4.6): `[client.pwa]` makes the storefront installable from the browser, with an offline ticket view.

---

## 2. How we work (applies to every sub-phase)

### 2.1 The TDD loop — "one sub-phase = one PR"

```text
1. Branch      git switch -c feat/p<phase>.<sub>-<slug>        (e.g. feat/p4.3-seat-holds)
2. RED         Write the sub-phase's tests (listed in this plan). Run `jac test` → they FAIL for the right reason.
               Commit: "test(p4.3): seat hold concurrency and expiry"
3. GREEN       Implement the minimum to pass. `jac test` → all green (new + all previous).
4. REFACTOR    Clean up with tests green. Validate every new .jac via the jac MCP (validate_jac) / `jac check`.
5. GATE        Local: pre-commit + pre-push hooks pass. Remote: every required CI check passes.
6. MERGE       Squash-merge the PR into main. Tick the box in this file. Only then start the next sub-phase.
```

**Definition of Done (per sub-phase):**
- [ ] Every test in the sub-phase's "Tests" list exists and passes, and no earlier test regressed.
- [ ] `jac fmt --check .`, `jac check --lint .` and `jac check` are clean.
- [ ] New endpoints are registered in the **tenant-isolation registry** (§2.3) and have cross-tenant tests.
- [ ] Any new external side effect goes through `on_commit` or the outbox, with a replay test (§25/§29 of the architecture doc).
- [ ] UI sub-phases: the Playwright E2E happy path passes. Mobile: the device checklist is ticked.
- [ ] UI sub-phases: follow `design-system/africinemas/MASTER.md` (plus any page override). Run the **ui-ux-pro-max** skill's pre-delivery checklist (`references/pro-rules.md` for mobile). Screenshots at 375 / 768 / 1440 px attached to the PR.
- [ ] UI sub-phases: the E2E happy path passes on **both** the `mobile` (Pixel 7, 412 px, touch) and `desktop` (1440 px) Playwright projects. An automated check asserts **no horizontal overflow** and **tap targets ≥ 44 px** at 375 px.
- [ ] Docs updated: this file's checkbox, plus an ADR if a decision was made.

### 2.2 Test pyramid and where tests live

| Layer | Tool | Location | Runs in |
| --- | --- | --- | --- |
| Unit (pure logic: pricing, state machines, validators, QR signing) | `test` blocks / `.test.jac` annexes | beside the module in `core/` | pre-push, CI |
| API / integration (endpoints, auth, graph effects, multi-user) | `JacTestClient` with a fresh `tempfile.mkdtemp()` base_path per test | `tests/api/` | pre-push, CI |
| Concurrency (races: holds, redemption, callbacks, idempotency) | real `jac run` server + parallel HTTP (`flow`/`wait`) | `tests/concurrency/` | CI |
| Tenant isolation (A → B on every endpoint) | shared two-tenant fixture + endpoint registry | `tests/isolation/` | CI |
| AI | `MockLLM` (no network, no key) | `tests/ai/` | CI |
| Web E2E | Playwright (`@playwright/test`) against `jac run`, with two projects: `mobile` (Pixel 7 emulation, touch) and `desktop` (1440×900). Every spec runs in both | `e2e/` | CI |
| Load | Python load script (`tests/load/`) | manual + pre-release |
| Mobile | shared-logic unit tests + `jac check --app mobile` + web build; device checklist | `mobile/` | CI (+ manual) |

Rules (from the Jac testing guide): never name files `test_*.jac`. Each test builds its own data (tests run in parallel workers and must not depend on each other). Never call a real LLM or Daraja in CI.

### 2.3 Tenant-isolation registry

`tests/isolation/registry.jac` lists every endpoint with an A→B probe. A **meta-test** compares it against the endpoints the server really exposes (`jac run --faux` output). An endpoint missing from the registry fails CI, so no new endpoint can skip the isolation tests.

### 2.4 Conventions

- **Commits:** Conventional Commits (`feat|fix|test|refactor|docs|chore|ci(scope): …`), enforced by a commit-msg hook and a PR-title check.
- **Branches:** `feat/…`, `fix/…`, `chore/…`, `docs/…`. No direct commits to `main`.
- **Decisions:** Architecture Decision Records (ADRs) in `docs/adr/NNNN-title.md`.
- **Secrets:** `.env` (gitignored) locally, GitHub Actions secrets in CI, never in `jac.toml` (use `${VAR}` interpolation).

---

## 3. Target repository layout

```text
africinemas/
├── jac.toml                    # workspace: [apps.web] [apps.desktop] [apps.mobile], profiles, [byllm], [scale.*]
├── main.jac                    # web app entry (server + client mount)   (exact names follow `jac create` output)
├── core/                       # server-side domain (shared by all apps)
│   ├── tenancy/  identity/  authz/        # tenants, memberships, roles, authorize()
│   ├── catalog/                           # venues, auditoriums, seat layouts, movies, screenings, pricing
│   ├── booking/                           # seat slots, holds, orders, bookings, idempotency
│   ├── payments/                          # provider interface, daraja adapter, simulator, ledger, workers
│   ├── ticketing/                         # issuance, QR signing, redemption
│   ├── reporting/  audit/  ai/            # dashboard aggregates, audit log, by-llm features
│   └── testing/                           # fixtures: two-tenant world, users, clock control
├── shared/                     # client-side, framework-agnostic: API wrappers, view models, formatters (NO HTML)
├── web/                        # React DOM pages/components (jac-shadcn): storefront, back-office, scanner
├── desktop/                    # desktop app entry: imports web client root; [desktop] config
├── mobile/                     # mobUI screens, theme, navigation, .native.jac camera variant
├── tests/  api/ concurrency/ isolation/ ai/ load/
├── e2e/                        # Playwright specs
├── scripts/                    # doctor.sh, seed_demo.jac, dev helpers
├── docs/  IMPLEMENTATION_PLAN.md  adr/  architecture.md (tracked copy of resources/ doc)
└── .github/  workflows/ ci.yml nightly.yml release.yml · CODEOWNERS · PULL_REQUEST_TEMPLATE.md · dependabot.yml
```

---

## 4. Phases and sub-phases

Legend: **T** = tests written first (RED), **I** = implementation, **✓** = exit gate.

### Phase 0 — Environment, scaffold, quality gates (Week 1, days 1–2)

- [x] **0.1 Toolchain doctor**
  - **T:** `scripts/doctor.sh` asserts: `jac --version` == pinned version, `jac mcp` reachable, git configured, `pre-commit`/`gh` present. It exits non-zero on any miss.
  - **I:** Install `uv` and `gh` into `~/.local/bin` from checksum-verified GitHub release tarballs (no sudo), then `uv tool install pre-commit`. Pin the Jac version in **`.jac-version`**, the single source of truth read by the doctor and (later) CI. `jac.toml` doesn't exist until 0.2, which adds `[project] jac-version` from this file.
  - **✓** `scripts/doctor.sh` exits 0.
- [x] **0.2 Scaffold with Jac's recommended commands**
  - **I:** `jac create --use jac-shadcn` in the repo root (web-app + shadcn primitives). Then `jac create --app desktop --kind desktop` and `jac create --app mobile --kind mobile`, which turns the project into a workspace. `jac setup mobile` (Expo scaffold). Add `[client.pwa]` if useful.
  - **T:** a smoke test (`core/health.jac` + test) asserts the server exposes `/health`. Also `jac run --faux` lists the smoke endpoint.
  - **✓** `jac check` passes for all three apps (0 errors; warnings in generated template code are ratcheted from P0.4), `jac test` is green (`[test] directory = "tests"`), and `jac run --dev web` serves the page. **Spike:** confirm the `desktop` app can import the web app's client root (ADR-0001: shared `web/AppRoot.jac`, `[desktop] backend` = the shared server URL).
- [x] **0.3 Test harness & fixtures**
  - **T:** tests for the harness itself (`tests/support/harness_tests.jac`): `two_tenant_world()` registers six distinct actors (`owner_a`, `staff_a`, `customer_a`, `owner_b`, `staff_b`, `customer_b`), `as_actor()` switches identity, `anonymous()` gets 401, and each world has an isolated store. Clock tests (`tests/unit/clock_tests.jac`): freeze, advance and reset, and control is refused unless `AFRICINEMAS_CLOCK_CONTROL=1`.
  - **I:** `tests/support/harness.jac` (test code stays out of the shipped app, so not `core/testing/`), `core/clock.jac` (domain code must use `clock.now()`, never `datetime.now()`), and **`scripts/test.sh`**, the one way to run tests locally, in pre-push and in CI. It sets `JAC_TEST_STRICT=1` (otherwise `jac test` silently *skips* a file whose local import is missing) and uses 1 worker locally and `auto` on CI. The `[environments.*]` profiles moved to 0.7. Tenants are attached to the actors in 2.2.
  - **✓** 10/10 green on two consecutive runs, and no temp stores left behind.
- [ ] **0.4 Pre-commit hooks** (`.pre-commit-config.yaml`)
  - pre-commit stage: `jac fmt --check`, `jac check --lint`, trailing-whitespace, end-of-file-fixer, check-yaml, check-toml, check-json, check-merge-conflict, check-added-large-files, detect-private-key, `gitleaks`, `no-commit-to-branch` (main)
  - commit-msg stage: `conventional-pre-commit`
  - pre-push stage: `jac check` (full type check) + `scripts/test.sh` (strict mode)
  - **T:** a scripted self-test that feeds a mis-formatted `.jac`, a fake secret and a bad commit message, and asserts each is rejected.
  - **✓** `pre-commit run --all-files` passes on a clean tree.
- [ ] **0.5 GitHub Actions CI** (`.github/workflows/ci.yml`, on PR + push to main, `concurrency` cancel-in-progress)
  - Jobs (these become the **required status checks**): `quality` (fmt, lint, typecheck) · `test` (unit/api/isolation/ai) · `concurrency` · `build-web` · `build-desktop` (linux) · `build-mobile-web` · `e2e` (Playwright) · `security` (gitleaks, `actions/dependency-review-action`, Trivy fs scan) · `pr-title` (semantic PR title).
  - Install the pinned Jac binary in CI (method verified in this sub-phase), and cache `~/.cache/jac`, `.jac/venv` and node deps.
  - `nightly.yml`: Daraja sandbox integration tests (secrets) + Android APK build. `release.yml` (tag `v*`): APK + desktop artifact + deploy.
  - **✓** A throwaway PR shows every check running and green.
- [ ] **0.6 Repo governance files**
  - `CODEOWNERS`, `PULL_REQUEST_TEMPLATE.md` (DoD checklist), issue templates, `CONTRIBUTING.md` (the TDD loop), `SECURITY.md`, `.editorconfig`, `dependabot.yml` (github-actions, npm, pip), `.gitignore` (+ `.jac/`, `.env`, `node_modules/`), `.env.example`.
  - Copy the architecture doc to tracked `docs/architecture.md` (`resources/` is gitignored today).
  - **Branch protection for `main` (you apply it in GitHub → Settings → Rules):** require a PR before merging; require the status checks listed in 0.5; require branches to be up to date; require conversation resolution; require linear history (squash merges only); block force pushes and deletions; apply to administrators. Required approvals: **1 if you have teammates, 0 if solo** (GitHub doesn't let you approve your own PR). Optional: require signed commits.
  - **✓** The protection rules are active. A direct push to `main` is rejected.
- [ ] **0.7 Config, profiles & secrets**
  - `jac.toml` profiles: `development` / `test` / `production`. `[byllm.model] default_model = "gemini/gemini-2.0-flash"` (model confirmed at P8), key read from `${GOOGLE_API_KEY}`. Daraja: `${DARAJA_CONSUMER_KEY}`, `${DARAJA_CONSUMER_SECRET}`, `${DARAJA_SHORTCODE}`, `${DARAJA_PASSKEY}`, `${DARAJA_CALLBACK_BASE}`. `JAC_SERVE_AUTH_SECRET`.
  - **T:** a config test asserts that the production profile has `docs_enabled=false`, `graph_enabled=false`, an auth secret required, and `max_body_bytes` ≤ 5 MB (§138 baseline). Also that the built-in platform `admin` account can't boot with its **default password** in production (found in P0.2, ADR-0001).
  - **✓** The config tests are green.

- [ ] **0.8 Design system (UI/UX foundation)** — uses the project skill `.claude/skills/ui-ux-pro-max`
  - **I:** Generate and persist the design system: `python3 .claude/skills/ui-ux-pro-max/scripts/search.py "cinema ticket booking entertainment" --design-system --persist -p "AfriCinemas" --output-dir .`, then review and adjust it with you (brand colours, fonts, light/dark). Add page overrides for `storefront`, `seat-map`, `checkout`, `back-office`, `scanner`, each specifying its **phone and PC layouts** (per §1.1). Define the responsive shell components once: `AppShell` (sidebar ↔ drawer), `BottomActionBar`, `ResponsiveTable` (table ↔ cards). Map the tokens into the jac-shadcn theme (`[jac-shadcn]` + `jac retheme`) and the mobUI `theme.jac` token objects, so web, desktop and mobile share one palette.
  - **T:** a token test asserts every foreground/background pair in the theme meets WCAG AA contrast (4.5:1 text, 3:1 large text/UI). A Playwright visual smoke checks the theme is applied (Button, Card, Input render with the token colours). A shell test on both Playwright projects checks the sidebar is visible on desktop and a drawer on mobile, and that the page has no horizontal overflow at 375 px.
  - **✓** `MASTER.md` approved by you and committed. Theme tokens are live in the scaffold.

### Phase 1 — Platform spikes, encoded as tests (Week 1, day 3)

Each spike is a test file whose assertions are the pass criteria from §138. The result is recorded in an ADR, and a fallback is adopted if a spike fails.

- [ ] **1.1 S1** A server flow creates a per-tenant service principal and nodes owned by it. **ADR-0002 (tenant ownership model).**
- [ ] **1.2 S2** Staff reach tenant nodes via `MemberOf` → `StaffGroup` + `allow_group`. Removing the membership revokes access immediately. Tenant B's staff see nothing.
- [ ] **1.3 S4** An anonymous `def:pub` records a receipt, and a system-identity scheduled job processes it into tenant-owned nodes.
- [ ] **1.4 S3/S6** `_before_request` can read the host header / reject a request. Staff token TTL can be set below 1 day.
- **✓** All spike ADRs are merged. Phases 2+ follow the chosen model.

### Phase 2 — Identity, tenancy, authorization (Week 1, days 3–5)

- [ ] **2.1 Tenant & control-plane archetypes** (`Tenant`, `TenantSlug` index, `StaffGroup`, `MemberOf`, `CustomerProfile`)
  - **T:** slug validation (charset, length, reserved words); unique slug under concurrent create (converges to one); tenant state enum transitions.
- [ ] **2.2 Owner signup → atomic tenant provisioning** (§92)
  - **T:** signup creates the tenant + principal + group + OWNER membership in one transaction; an injected failure leaves no partial tenant; a duplicate slug returns a typed error.
- [ ] **2.3 Roles, permissions, `authorize(ctx, action, resource)`** (§14, §15, §129)
  - **T:** a parametrized role × permission matrix (OWNER, TENANT_ADMIN, BOX_OFFICE_AGENT, USHER, FINANCE_MANAGER, …); deny-by-default for unknown actions; venue-scoped roles are denied other venues.
- [ ] **2.4 TenantContext resolution + isolation harness**
  - **T:** context is resolved server-side from membership; a forged tenant selector is rejected; the isolation registry + meta-test is in place (§2.3).
- [ ] **2.5 Staff invitations & lifecycle** (via `app_tokens`)
  - **T:** invite → accept assigns the role; a token is single-use under concurrent accepts; expired tokens are rejected; disabling or changing a role takes effect on the next call even with the old JWT.
- [ ] **2.6 Customer accounts per tenant**
  - **T:** a customer registers on tenant A's storefront → a `CustomerProfile` for A only; the same person on B gets a separate profile; a customer can't call staff endpoints.
- [ ] **2.7 Web UI: auth, onboarding wizard shell, role-aware navigation** (jac-shadcn, `AuthGuard` layouts)
  - **T (E2E, mobile + desktop):** owner signs up → creates a cinema → lands on the dashboard; an usher sees only the scanner nav; logout works. On mobile, navigation is through the drawer.

### Phase 3 — Cinema setup (Week 2, days 1–3)

- [ ] **3.1 Venues & auditoriums CRUD** — **T:** CRUD + authz + isolation; auditorium names unique per venue.
- [ ] **3.2 Seat layouts with versioning** (§21, §22) — **T:** layout validation (unique seat labels, grid bounds, seat types enum); publishing freezes a version; editing a published layout creates v2; screenings keep their version.
- [ ] **3.3 Seat layout designer UI** — **T (E2E, desktop):** build a 5×8 grid with an aisle and wheelchair seats, save, publish, reload, and it's identical. **(mobile):** shows a read-only preview + "use a larger screen" notice.
- [ ] **3.4 Movies + poster upload** (§56) — **T:** CRUD; upload rejects wrong MIME / oversize; storage key is `tenant/{id}/media/{uuid}`; a cross-tenant media URL is denied.
- [ ] **3.5 Screenings: scheduling & lifecycle** (§120, §121) — **T:** overlap in the same auditorium is rejected (runtime + cleaning buffer); state machine transitions (invalid ones raise); publish creates exactly one `SeatSlot` per seat and the storefront projection on `root.shared`.
- [ ] **3.6 Pricing & server-side quote** (§27, §28) — **T:** a table-driven quote: ticket type × seat zone × day-part surcharge; the quote ignores client-supplied prices; money uses integer cents (KES).
- [ ] **3.7 Back-office UI for 3.1/3.4–3.6** — **T (E2E):** create venue → screen → movie → screening → publish; it appears on the storefront.

### Phase 4 — Storefront & booking engine (Week 2, days 3–5)

- [ ] **4.1 Public storefront reads** (`/c/{slug}`: home, movie, screening; §41) — **T:** anonymous reads see only published data; unpublished is invisible; tenant A's slug never returns B's data.
- [ ] **4.2 Seat availability** — **T:** a lazily expired hold shows as AVAILABLE; BLOCKED/HOUSE are not sellable; the response carries text states (accessibility, §102).
- [ ] **4.3 Seat holds** (§24, §25) — **T:** hold/release/extend; per-customer cap; **concurrency: 50 parallel holds on one seat → exactly 1 succeeds**; overlapping multi-seat holds → no partial holds.
- [ ] **4.4 Hold expiry sweeper** (`@schedule`) — **T:** idempotent when run twice (it runs on every replica); never releases `PAYMENT_PENDING` holds.
- [ ] **4.5 Orders/bookings with price snapshot & idempotency** (§26, §27) — **T:** same idempotency key → same booking (including concurrently); the snapshot is unchanged after a price edit.
- [ ] **4.6 Storefront UI: seat map & checkout shell (mobile-first)** — **T (E2E, mobile + desktop):** pick a screening → select 2 seats (tap on mobile, click/keyboard on desktop) → hold timer shows → proceed to pay. On mobile: the seat map fits the width and can be zoomed, and the sticky bottom bar shows the seats and total. Keyboard-only seat selection works on desktop. Decide on `[client.pwa]` here.
- [ ] **4.7 Load test (spike S5)** — **T:** 200 concurrent hold attempts on one screening: zero double-holds, p95 latency and 409-rate within the targets recorded in ADR-0006.

### Phase 5 — M-Pesa payments via Daraja (Week 3, days 1–3)

- [ ] **5.1 `PaymentProvider` interface + simulator** — **T:** the simulator scripts success/fail/cancel/timeout/late-success; the payment state machine (§32) rejects invalid transitions.
- [ ] **5.2 Daraja adapter** (OAuth token cache, STK push, STK query, C2B registration later) — **T:** HTTP-mocked contract tests from recorded sandbox fixtures; token refresh; timeouts/retries; no secrets in logs.
- [ ] **5.3 `initiate_payment`** (§29) — **T:** creates a `PaymentIntent` + extends the hold to `PAYMENT_PENDING`; **a forced serialization replay still produces exactly one STK call** (`on_commit`/outbox); the idempotency key prevents a double initiate.
- [ ] **5.4 Callback → receipt → verified finalize** (§33–§35) — **T:** the callback only stores a receipt; the worker verifies via STK query; finalize makes Payment SUCCESS + Booking CONFIRMED + SeatSlots SOLD + Tickets ISSUED atomically; **3 duplicate callbacks → one ticket set**; amount mismatch → `NEEDS_ATTENTION`; late success after release → `NEEDS_ATTENTION` + refund task.
- [ ] **5.5 TIMEOUT/UNKNOWN resolver job + ledger entries** (§37, §124) — **T:** stuck intents are resolved via status query; ledger entries are append-only and balance per booking.
- [ ] **5.6 Checkout UI** (enter phone → "check your phone" → live status) — **T (E2E, simulator, mobile + desktop):** success path shows the ticket; a failure releases the seats with a message. The M-Pesa phone field uses `inputmode="tel"` and is validated inline.
- [ ] **5.7 Daraja sandbox end-to-end** (nightly job + manual; callback via a Cloudflare Tunnel URL) — **✓** A real sandbox STK payment produces a ticket.

### Phase 6 — Tickets, scanning, box office (Week 3, days 3–4)

- [ ] **6.1 Ticket issuance & QR** (§46) — **T:** the QR payload is an opaque HMAC-signed reference with no PII; a tampered signature is rejected; references are unique.
- [ ] **6.2 Redemption** (§47) — **T:** valid → USED; second scan → `ALREADY_REDEEMED`; **concurrent double-scan → exactly one success**; wrong screening/tenant/voided/refunded are rejected; only usher-capable roles may scan.
- [ ] **6.3 Customer tickets** (view, resend via `on_commit` email) — **T:** a customer sees only their own tickets; resend is rate-limited.
- [ ] **6.4 Web scanner page** (camera QR via an npm lib; manual entry fallback) — **T (E2E):** manual-entry redeem flow; the camera component is unit-tested with an injected decoder.
- [ ] **6.5 Box-office walk-in sale** (counter mode: cash or M-Pesa at the counter) — **T:** a cash sale creates a confirmed booking + ledger entry attributed to the agent; the agent can't sell for another venue.

### Phase 7 — Owner dashboard & audit (Week 3, day 5)

- [ ] **7.1 Reporting aggregates** (§76, §77) — **T:** against a fixture graph with known numbers: revenue, tickets sold, occupancy %, top movies, per-venue drill-down; refunds are subtracted.
- [ ] **7.2 Audit log** (§66, §67) — **T:** every sensitive endpoint emits exactly one `AuditEvent` (a registry-driven meta-test); owners can read but not delete audit events.
- [ ] **7.3 Dashboard UI** (charts) — **T (E2E, mobile + desktop):** after a seeded sale the dashboard shows the matching totals. On mobile, KPI tiles stack and charts stay legible.

### Phase 8 — AI features with `by llm` (Gemini) (Week 4, days 1–2)

- [ ] **8.1 LLM plumbing** — **T:** MockLLM harness; timeout and error → graceful fallback; prompts contain tenant-scoped data only, never customer PII.
- [ ] **8.2 Synopsis & promo-copy generator** (owner) — **T:** structured `obj` output (tagline, synopsis, social post) respects length limits.
- [ ] **8.3 "What should I watch tonight?"** (customer) — **T:** recommendations only reference real, published, on-sale screenings of *this* tenant; hallucinated IDs are filtered out.
- [ ] **8.4 Natural-language showtime search** — **T:** text → typed `ScreeningFilter` obj → deterministic graph query; unsafe or empty parses fall back to a keyword search.
- [ ] **8.5 Dashboard insights narrative** — **T:** the narrative cites only numbers from 7.1's aggregates.
- **✓** One live smoke run with a real `GOOGLE_API_KEY` (manual).

### Phase 9 — Desktop app (Week 4, day 2)

- [ ] **9.1 Desktop wraps the web client** (`kind = "desktop"`, `backend = "${AFRICINEMAS_SERVER_URL}"`, counter-friendly window config) — **T:** CI `jac build desktop` succeeds (linux); a smoke launch under xvfb loads the login page. Manual checklist on Windows if a counter PC needs a `.exe` (build on Windows; no cross-compile).
- [ ] **9.2 Desktop niceties** (`@jac/desktop`: export a report via `dialog`+`fs`, OS notifications for new walk-in queue) — **T:** unit tests with the plugin bridge mocked.

### Phase 10 — Mobile app, native mobUI (Week 4, days 2–4)

Scope: **customer** (browse, book, pay, my tickets), **usher scanner** (camera), **box-office quick sale**, **owner summary**. Configuration tools (seat designer, pricing, staff management) stay on web/desktop.

- [ ] **10.1 Shared client layer** (`shared/`: typed API wrappers, view models, formatters) — **T:** unit tests; the web app is refactored to use the same wrappers with no regressions.
- [ ] **10.2 Mobile scaffold, theme tokens, navigation, auth** (`expo-secure-store` token) — **T:** `jac check --app mobile` passes; `jac build mobile --platform web` succeeds in CI; login screen checklist.
- [ ] **10.3 Customer flows** — **T:** view-model tests; device checklist: book 2 seats → pay (sandbox) → ticket QR displayed.
- [ ] **10.4 Usher scanner** (`expo-camera` via `[dependencies.npm.native]`, `icon.jac` / `icon.native.jac`-style variant pair; web variant = manual entry) — **T:** decoder → redeem flow unit-tested; device checklist: a real scan redeems, a second scan is rejected.
- [ ] **10.5 Box office & owner summary screens** — **T:** view-model tests; device checklist.
- [ ] **10.6 Android APK** (`jac build mobile --platform android`; nightly/release CI) — **✓** The APK installs on a physical phone and completes the demo script.

### Phase 11 — Hardening, deploy, demo (Week 4, days 4–5)

- [ ] **11.1 Security pass** — **T:** the full isolation suite is green; production-config assertions; CSP/security headers at the edge; rate limits on hold/pay/scan; the threat-model items from §131 relevant to the MVP each have a test.
- [ ] **11.2 Deployment** — **I:** a single VM running the Jac server with external Postgres (`JAC_DB_URL`) behind a Cloudflare Tunnel (public HTTPS for the web app, the desktop backend URL and Daraja callbacks). Release workflow deploys on tag. **✓** Health checks green in production.
- [ ] **11.3 Demo data & script** — `scripts/seed_demo.jac` (2 cinemas, movies, screenings, staff); a 5-minute demo script covering web, desktop and mobile.
- [ ] **11.4 Docs** — README (setup, run, test), architecture summary, ADR index.

---

## 5. Schedule & risk

| Week | Phases | Risk / mitigation |
| --- | --- | --- |
| 1 | P0, P1, P2 | Spike failures → switch to the §138 fallback the same day; don't sink time |
| 2 | P3, P4 | Seat designer UI can overrun → start with a grid editor, polish later |
| 3 | P5, P6, P7 | Daraja sandbox flakiness → the simulator keeps CI and development unblocked |
| 4 | P8, P9, P10, P11 | **Mobile is the tightest item.** If behind: ship scanner + my tickets first (10.4, 10.3) and drop 10.5 |

Buffer: each week's last half-day is reserved for catch-up and refactoring.

## 6. Verification (end-to-end, before submission)

1. `scripts/doctor.sh` && `pre-commit run --all-files` && `jac check` && `jac test` → all green locally.
2. CI on `main`: every required check is green. The nightly Daraja + APK job is green.
3. Production: the demo script end-to-end: owner onboarding (web) → screening published → customer books on mobile with a sandbox M-Pesa payment → counter sells a walk-in seat (desktop) → usher scans both tickets (mobile) → dashboard shows the correct totals → AI recommendation works.
4. Isolation suite: tenant A's credentials can't reach any tenant B resource on any endpoint.

## 7. Open items (decide by the phase noted)

- Deployment host for P11 (VM provider). Default: any small Ubuntu VM + Cloudflare Tunnel.
- Gemini model name (`gemini-2.0-flash` vs newer): confirm at P8.
- Team size, which sets required PR approvals (0.6).
