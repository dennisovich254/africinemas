# AfriCinemas — Implementation Plan

> **Status:** Draft v1 (2026-09-26), awaiting approval
> **Timebox:** 4-week Jac hackathon
> **Architecture reference:** `docs/architecture.md` ("§n" below means a section of that document)
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

Optional (decided at 4.6: deferred to Phase 6, with tickets): `[client.pwa]` makes the storefront installable from the browser, with an offline ticket view.

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

`tests/isolation/registry.jac` lists every endpoint with its scope and an A→B probe. A **meta-test** compares it against the endpoints the app really serves (its `/openapi.json` routes; `jac run --faux` headings are unreliable, JI-004). An endpoint missing from the registry fails CI, so no new endpoint can skip the isolation tests.

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
- [x] **0.4 Pre-commit hooks** (`.pre-commit-config.yaml`, installed with `pre-commit install`)
  - pre-commit stage: trailing-whitespace, end-of-file-fixer, mixed-line-ending, check-yaml/toml/json, check-merge-conflict, check-added-large-files (500 KB), detect-private-key, no-commit-to-branch (`main`), **gitleaks** (`gitleaks-system` with `pass_filenames: false`, because upstream omits it, making gitleaks scan 0 bytes and pass), `jac fmt --check`, and `scripts/jac_lint.sh` (fails on any lint finding, since `jac check --lint` exits 0 on them: JI-010). Vendored `components/ui/` is excluded from the formatter and linter.
  - commit-msg stage: `conventional-pre-commit`.
  - pre-push stage: `scripts/check_warnings.sh` (0 errors; warnings ≤ `.jac-warnings-baseline` = 76, and the count can only go down, with `--update` to lock in gains) and `scripts/test.sh --quick` (strict; unit, isolation and API smoke tests; since P3.5a, the full suite runs in CI only).
  - **T:** `scripts/hooks_selftest.sh` builds a throwaway repo and asserts that each gate rejects bad input and accepts clean input: bad formatting, a lint violation, a private key, a staged GitHub token, `update stuff` as a commit message, a commit on `main`, and warnings over the baseline. 13/13 pass. `scripts/doctor.sh` also checks gitleaks and the installed hooks.
  - **✓** `pre-commit run --all-files` passes (it fixed a missing newline in `styles/global.css`), and the pre-push stage passes.
- [x] **0.5 GitHub Actions CI** (`.github/workflows/ci.yml`, on PR + push to `main`, `concurrency` cancel-in-progress, `permissions: contents: read`, **every action pinned to a full commit SHA**)
  - Jobs now, which become the **required status checks**: `pr-title` (Conventional Commits) · `quality` (the same pre-commit hooks as local commits, plus `scripts/check_warnings.sh`) · `test` (`scripts/test.sh`, strict, one worker per core) · `build-web` (artifact `web-dist`) · `build-desktop` (linux; system packages pre-installed per JI-005; artifact `desktop-linux`) · `build-mobile-web` · `security` (gitleaks over the full history, and `dependency-review-action` failing on high severity for PRs).
  - Jobs added with their first tests: `e2e` (Playwright) in **0.8**, `concurrency` in **4.3**. `nightly.yml` (Daraja sandbox, Android APK) arrives in **5.7/10.6**, and `release.yml` in **11.2**. A Trivy scan was dropped for now, since dependency review + gitleaks + GitHub secret scanning (already on) cover the MVP.
  - Jac is installed by **`scripts/install_jac.sh`**, which downloads `jac-<.jac-version>-linux-x86_64` from the official `jaseci-labs/jaseci` release and **requires** its `.sha256` (the upstream `install.sh` only warns if it's missing). The CI binary is byte-identical to the dev box's (`ead9f12e…`). The shared composite action `.github/actions/setup-jac` caches the binary/runtime and `.jac/venv` + node deps. `scripts/install_gitleaks.sh` and `scripts/install_actionlint.sh` do the same for those tools, and **actionlint** was added as a pre-commit hook.
  - **✓** All 7 checks green on PR #6 (second run). The first run failed 4 checks, which led to JI-012 (the mobile template doesn't build for web), JI-013 (workspace build output path), the missing Dependency graph setting, and a warning count that depends on the environment (CI 74 vs local 76; the baseline stays 76, the local ceiling).
- [x] **0.6 Repo governance files**
  - `.github/CODEOWNERS`, `.github/PULL_REQUEST_TEMPLATE.md` (a summary and UI screenshots; the Definition of Done stays in this plan, not in PR descriptions, per the owner on 2026-09-29), issue forms (bug report, feature request; blank issues off; security reports routed to private advisories), `CONTRIBUTING.md` (setup, the RED→GREEN loop, gates), `SECURITY.md`, `.editorconfig`, `.github/dependabot.yml` (GitHub Actions only; Dependabot can't read `jac.toml`, so Jac/Python/npm deps are bumped by hand), `.env.example` (names only, no values), and **`docs/architecture.md`**, the tracked, canonical copy of the architecture doc. `resources/` stays local and git-ignored.
  - **T:** `scripts/check_governance.sh` (RED: 28 failures → GREEN) asserts that the files exist, the PR template has its summary and screenshot sections, CONTRIBUTING covers the workflow, `.env.example` documents every variable *name* used in `.env` and `jac.toml` without values, and `.env`/`.mcp.json`/`.claude/`/`resources/` are ignored. It runs in CI's `quality` job.
  - **Branch protection (applied by the owner as a ruleset on `main`):** PR required (0 approvals, solo), conversation resolution, linear history, no force-push or deletion, no bypass, and the 7 required checks from 0.5. The repo allows squash merges only. **To do (owner):** enable "Require branches to be up to date" (`strict`), "Automatically delete head branches", and private vulnerability reporting.
- [x] **0.7 Config, profiles & secrets** (corrected by the follow-up fix PR)
  - `jac.toml` profiles: `development` (default), `test`, `production`. Production uses a profile only for `[scale.*]`: **Jac's built-in admin bootstrap is disabled** (`[scale.admin] enabled = false`; otherwise it creates `admin`/`changeme`).
  - **All `[serve]` hardening lives in `deploy/production.env`** as `JAC_SERVE_*` env vars (`JAC_PROFILE=production`, `JAC_SERVE_DOCS=false`, `JAC_SERVE_GRAPH=false`, `JAC_SERVE_AUTH_TOKEN_TTL_DAYS=1`, `JAC_SERVE_MAX_BODY_BYTES=5242880`). Secrets (`JAC_SERVE_AUTH_SECRET`, `JAC_DB_URL`) come only from the deployment's secret store.
  - Shaped by **JI-014** (the running server ignores profile overrides for `[serve]`; the config API turns nested ones into partial dicts) and **JI-015** (`${VAR}`/`${VAR:?msg}` keep their literal text when unset).
  - **T (authoritative):** `tests/integration/production_server_tests.jac` boots a **real server** from a temp copy of the repo with `deploy/production.env`, and asserts over HTTP: `/docs`, `/openapi.json`, `/graph` → 404; a 6 MB body → 413; `admin`/`changeme` refused; `app_info` still works. It drops its own database afterwards. Mutation-checked: removing the body limit makes it fail.
  - **T (fast):** `tests/unit/config_tests.jac` (7 tests): settings via `ServeSettings.load`, every profile loads, the admin bootstrap is off, no required-env placeholders, no `[environments.*.serve]` tables, `production.env` holds no secrets, and development needs no prod secrets.
  - **Lesson:** security settings are tested against a **running server over HTTP**, not only through the config API. The first version of P0.7 passed its unit tests while `/docs` and `/graph` would have stayed public.
  - Moved to **8.1**: the `[byllm.model]` Gemini config and the `GEMINI_API_KEY` vs `GOOGLE_API_KEY` question.
**Theming model (decided 2026-09-27):** every tenant gets the same structure and behaviour (code), but its **own branding (data)**. A theme is a typed set of **tokens**: named colour roles for light and dark, fonts from an **allowlist**, and a radius preset. Tenants and AI never supply CSS, HTML or JS (architecture §55). A deterministic **validator** enforces WCAG AA contrast in both modes and **auto-repairs** failing colours. The tenant theme fully brands the **storefront** (plus tickets, emails, and the mobile app while browsing that cinema); the **back-office/desktop** keep the platform look with only the tenant's logo and accent. The approved platform default: **light** = the P0.8 preview (https://claude.ai/artifact/5pwN5rnD7sgZzYtqgStde5: warm off-white, spotlight gold, calm back-office, Bebas Neue + Outfit); **dark storefront** = **"Espresso Noir"** (warm brown-black, sepia, brass gold), chosen over the original indigo on 2026-09-27 from the options at https://claude.ai/artifact/UjyJo3LuqG5hkRpku11wDF; the **back-office dark** mode matches it (slightly lifted, brass actions). The unchosen options (Projector Black, Velvet Curtain, Blackout Crimson) are candidate tenant presets for 3.8. Design work uses the **local-only** Claude Code skill `ui-ux-pro-max` (`.claude/` is git-ignored; install from https://github.com/nextlevelbuilder/ui-ux-pro-max-skill at commit `d62fe62f88acb6755d2e5819a1b1e19eb447a8f1`, then point the `SKILL.md` script paths at `.claude/skills/ui-ux-pro-max/`). Its output **is** committed.

- [x] **0.8a Theme model & validator** (pure logic, `core/theming/tokens.jac`)
  - **I:** `ThemeTokens` (20 typed colour roles per mode), `Theme` (light + dark + fonts + radius), a strict `#RRGGBB` parser (lower-case is normalised; anything else raises `InvalidThemeValue`, so a colour can't carry CSS), font and radius allowlists, WCAG contrast maths, `validate_theme()` (28 rules: text pairs ≥ 4.5:1, UI pairs ≥ 3:1), `repair_theme()` (first pulls surface fills onto the background's dark/light side, then moves only each failing colour's lightness, keeping its hue), and `DEFAULT_THEME` (the approved preview values). `Theme.as_dict()` / `ThemeTokens.as_dict()` for value comparison (JI-016).
  - **T:** `tests/unit/theme_tests.jac` (8 tests): WCAG reference ratios (21:1, 4.48:1), the default theme passes all rules in both modes, strict hex (including `#123456;}body{…`), the allowlists, rule-by-rule reporting, **200 random palettes repaired**, a valid theme is left unchanged, hue is kept. An extra local stress run repaired **5,000 random palettes with 0 failures**.
- [x] **0.8b Theme → CSS & app wiring**
  - **I:** `core/theming/css.jac`: `theme_css(theme, surface)` renders validated tokens as shadcn variables plus `--ac-*` extras, scoped per surface (`[data-surface="storefront"|"backoffice"]`) with a `.dark` block (Tailwind v4 utilities read `var(--…)`, so one build serves every tenant's theme at runtime); `BACKOFFICE_THEME`; `styles/brand.css` **generated** by `scripts/gen_brand_css.jac` (a drift test forbids hand edits); `web/theme/ThemeProvider.jac` sets the surface and follows the device's dark mode **before the first paint** (`useLayoutEffect` + transitions suppressed while switching, so there's no light flash); body font Outfit via `jac retheme --font outfit`, display font Bebas Neue (`@fontsource/bebas-neue`, pinned); page title AfriCinemas; `mobile/theme.jac` palette = the storefront dark tokens (sync test).
  - **T (unit):** `theme_css_tests.jac` (7: scoping, every variable in both modes, fonts/radius, only validated hex, surface allowlist, back-office passes AA, `brand.css` drift) and `mobile_theme_sync_tests.jac`.
  - **T (E2E, `e2e/theme_tests.jac`, Playwright driven from Jac, `scripts/e2e.sh`, CI job `e2e`):** light and dark tokens on a **Pixel 7 + 1440 px desktop** (computed colours from the tokens); the secondary button's *painted* colour stays on-theme and readable; **no flash of the light theme** (measured inside the page on the first painted frame); live switch to dark; fonts actually loaded; no sideways scroll at 375 px and ≥ 44 px tap targets; review screenshots at 375/768/1440 × light/dark (uploaded by CI).
  - Found by reviewing the screenshots: the outline button was captured mid-animation (pale). Root cause: dark mode was applied *after* first paint, which caused a light flash plus a 150 ms transition on every load for dark-device users. Fixed and covered by a deterministic test.
  - Jac issues: **JI-017** (closing JSX tags flagged W2001; the warning counter discounts only that false positive, baseline now 72) and **JI-018** (Python TypedDict keys rejected by `jac check`).
- [x] **0.8c Responsive shell components**
  - **I:** `AppShell` (sidebar on desktop ↔ drawer on mobile), `BottomActionBar` (sticky, safe-area aware), `ResponsiveTable` (table ↔ cards), all using theme tokens only.
  - **T (E2E, mobile + desktop):** sidebar vs drawer, the bottom bar stays visible, the table becomes cards under `md`, tap targets are ≥ 44 px, keyboard focus is visible.

### Phase 1 — Platform spikes, encoded as tests (Week 1, day 3)

Each spike is a test file whose assertions are the pass criteria from §138. The result is recorded in an ADR, and a fallback is adopted if a spike fails.

- [x] **1.1 S1** A server flow creates a per-tenant service principal and nodes owned by it. **ADR-0003 (tenant ownership model).**
- [x] **1.2 S2** Staff reach tenant nodes via `MemberOf` → `StaffGroup` + `allow_group`. Removing the membership revokes access immediately. Tenant B's staff see nothing. **ADR-0004.**
- [x] **1.3 S4** An anonymous `def:pub` records a receipt, and a system-identity scheduled job processes it into tenant-owned nodes. **ADR-0005.**
- [x] **1.4 S3/S6** `_before_request` can read the host header / reject a request. Staff token TTL can be set below 1 day. **ADR-0006 (both failed as posed; fallbacks adopted).**
- [x] **✓** All spike ADRs are merged (ADR-0003 to ADR-0006). Phases 2+ follow the chosen model.

### Phase 2 — Identity, tenancy, authorization (Week 1, days 3–5)

- [x] **2.1 Tenant & control-plane archetypes** (`Tenant`, slug index as atomic claims (ADR-0007), `StaffGroup`, `MemberOf`, `CustomerProfile`)
  - **T:** slug validation (charset, length, reserved words); unique slug under concurrent create (converges to one); tenant state enum transitions.
- [x] **2.2 Owner signup → atomic tenant provisioning** (§92; claim-first + compensation, ADR-0007; lifecycle aligned to §92-§94)
  - **T:** signup creates the tenant + principal + group + OWNER membership in one transaction; an injected failure leaves no partial tenant; a duplicate slug returns a typed error.
- [x] **2.3 Roles, permissions, `authorize(ctx, action, resource)`** (§14, §15, §129; ADR-0008)
  - **T:** a parametrized role × permission matrix (OWNER, TENANT_ADMIN, BOX_OFFICE_AGENT, USHER, FINANCE_MANAGER, …); deny-by-default for unknown actions; venue-scoped roles are denied other venues.
- [x] **2.4 TenantContext resolution + isolation harness** (ADR-0008 §P2.4)
  - **T:** context is resolved server-side from membership; a forged tenant selector is rejected; the isolation registry + meta-test is in place (§2.3).
- [x] **2.5 Staff invitations & lifecycle** (via `app_tokens`; ADR-0008 §P2.5: roles on the membership record, no escalation, no self-change; shift sessions (ADR-0006) move to 2.7)
  - **T:** invite → accept assigns the role; a token is single-use under concurrent accepts; expired tokens are rejected; disabling or changing a role takes effect on the next call even with the old JWT.
- [x] **2.6 Customer accounts per tenant** (ADR-0009)
  - **T:** a customer registers on tenant A's storefront → a `CustomerProfile` for A only; the same person on B gets a separate profile; a customer can't call staff endpoints.
- [x] **2.7a Staff shift sessions** (ADR-0006 §P2.7a: an expiring claim per (cinema, member), 8 h; `start_shift`/`end_shift`; every staff action requires an open shift)
- [x] **2.7b Web UI: auth, onboarding wizard shell, role-aware navigation; logout ends the shift** (jac-shadcn, `AuthGuard` layouts; the wizard reserves an optional **"Brand your cinema"** step, filled in by 3.8 and 8.5; skipping it gives the platform default theme)
  - **T (E2E, mobile + desktop):** owner signs up → creates a cinema → lands on the dashboard; an usher sees only the scanner nav; logout works. On mobile, navigation is through the drawer.

### Phase 3 — Cinema setup (Week 2, days 1–3)

- [x] **3.1 Venues & auditoriums CRUD** — **T:** CRUD + authz + isolation; auditorium names unique per venue.
- [x] **3.2 Seat layouts with versioning** (§21, §22) — **T:** layout validation (unique seat labels, grid bounds, seat types enum); publishing freezes a version; editing a published layout creates v2; screenings keep their version.
- [x] **3.3 Seat layout designer UI** — **T (E2E, desktop):** build a 5×8 grid with an aisle and wheelchair seats, save, publish, reload, and it's identical. **(mobile):** shows a read-only preview + "use a larger screen" notice.
- [x] **3.4 Movies + poster upload** (§56) — **T:** CRUD; upload rejects wrong MIME / oversize; storage key is `tenant/{id}/media/{uuid}`; a cross-tenant media URL is denied.
- [x] **3.5a Screenings: scheduling & lifecycle** (§120, §121) — **T:** overlap in the same auditorium is rejected (runtime + cleaning buffer), including under concurrent requests; state machine transitions (invalid ones raise); a screening pins the screen's published layout version (its `layout_id`) and keeps it when the screen's layout is edited and republished (3.2); a screen without a published layout can't be scheduled; a screen or a movie with screenings can't be deleted.
- [x] **3.5b Publishing a screening: seat inventory and storefront projection** (§4, §25, §121) — spike first: staff code writes a per-tenant `Storefront` node on the shared guest graph (`root.shared`) that anonymous callers can read but not change. **T:** publish creates exactly one `SeatSlot` per seat of the pinned layout (BLOCKED/HOUSE seats not sellable), also when two publishes race; the storefront projection holds only published, non-sensitive fields; unpublishing or cancelling removes it; another cinema's projection isn't reachable from this one's.
- [x] **3.6 Pricing & server-side quote** (§27, §28; one versioned price list per cinema, read by staff at any venue, changed with `tenant.settings.update`; day-parts in the cinema's time zone; a line never goes below its service fee; quotes record the price-list version for 4.5's snapshot) — **T:** a table-driven quote: ticket type × seat zone × day-part surcharge; the quote ignores client-supplied prices; money uses integer cents (KES).
- [x] **3.8 Tenant branding (manual)**, split in two (like 3.5):
  - [x] **3.8a Themes as versioned data** — the tenant's `Theme` stored as a draft, published as numbered versions and projected (checked again) to the public storefront, where `public_branding(slug)` serves it with its CSS; four presets (AfriCinemas, Projector Black, Velvet Curtain, Blackout Crimson); unreadable colours are repaired on save and each change reported (owner's choice, 2026-09-29); logo upload reusing 3.4's upload rules (kept with transparency, fitted to 512 × 512, published and rolled back with the theme); roll back = publish an earlier version again (ADR-0013). **T:** a tenant's storefront serves its own tokens while another tenant's doesn't change (isolation); an unvalidated/injected value is impossible to store; rollback restores the earlier version, logo included; only `tenant.settings.update` holders can change branding.
  - [x] **3.8b Branding UI** — Settings › Branding: presets, colour pickers (key colours, the rest under "More colours", light and dark) and fonts with a live storefront preview, logo upload, publish and version history with roll back (asks first); a minimal storefront shell at `/c/{slug}` wears the cinema's published theme (Phase 4 fills it in); the back-office header shows the cinema's logo. The cinema's accent stays off the back-office: it is checked for contrast against the storefront's colours, not the back-office's. **T (E2E, mobile + desktop):** pick a preset → publish → the storefront colours change; another cinema's storefront doesn't; review screenshots at 375/768/1440 in both modes.
- [x] **3.7 Back-office UI for 3.1/3.4–3.6, and the Staff page**, split in three (owner's choice, 2026-09-30):
  - [x] **3.7a Venues, screens and movies** — a Venues section manages the cinema's locations (add, edit, delete) and the Screens section each venue's screens (add, rename, delete), for staff with `venues.configure` (owner's review, 2026-09-30: separate sections, add forms folded behind their buttons); others who read seat plans see the screens without the controls. A Movies section (for `movies.create` holders) lists the cinema's films with posters, adds and edits them, uploads posters and deletes (after a confirmation). Server refusals show under the field they concern. **T (E2E, mobile + desktop):** add a venue, then a screen at it, rename it and open its layout; a taken name and a venue that still has screens are refused where they apply; read-only staff see no controls; add a movie, fix an invalid running time, upload a poster, edit it; deleting asks first; phone checks; review screenshots.
  - [x] **3.7b Screenings programme and prices** — a Screenings section (for `showtimes.create` holders) shows one screen's programme at a time: add screenings (movie, date and start time in the viewer's time zone; the form opens from "Add screening"), publish, unpublish, move and cancel (asked first). The server's draft and scheduled states are both shown as "Not published", and Publish makes both steps. A Prices section (for `tenant.settings.update` holders) edits the 3.6 price list: ticket types (codes made from the names), prices per seat zone in KES, time-of-day extras (days, times, amount; negative for a discount) and the service fee; a refused list shows every problem, in staff language. **T (E2E, mobile + desktop):** add a screening and publish it, then it's on the storefront; clashing and past times are refused under the start time; a screen without a published layout links to it; unpublish, move and cancel; set ticket types, zone prices, an extra and a fee, then reload; a list with problems lists them; box office sees neither page; phone checks; review screenshots.
  - [x] **3.7c Staff page** — the P2.5 endpoints: invite with a role, an optional venue and a note on who it's for (the one-time invitation link to copy and share), change roles, disable or re-enable, remove (asked first). An invitation page (`/invite/{token}`) lets the invitee sign in or create an account and come back to accept. Each member shows who they are: their sign-in email, which the server keeps only after checking it is theirs (`core/tenancy/identity.jac`; a request carries only the caller's root), and the inviter's note. **T (E2E, mobile + desktop):** invite a box-office agent at a venue, accept in a second browser context, change their role, disable them (their next action is refused), re-enable and remove them; a newcomer creates an account from the link and joins; a used link says so; staff without the permission see no Staff page; phone checks; review screenshots.
- [x] **3.9 AfriCinemas landing page** (`/` on the platform domain; replaces the P0.8b welcome placeholder; built to the ui-ux-pro-max "Funnel" pattern after review: a hero over a looping cinema-hall video generated for the page (docs/media-sources.md), three steps with examples of the product, one closing call; the video pauses, and stays still for reduce motion or data saver) — the page cinema owners (and hackathon judges) see first: what AfriCinemas does, how it works (create your cinema → set up screenings → sell tickets with M-Pesa → scan QR tickets), who it's for, and a "Create your cinema" call to action leading to `/signup`, plus "Sign in" for staff. Mobile-first, platform theme in light and dark, real product screenshots or live UI rather than stock art, no tenant data. Content lives in one typed module so copy changes don't touch layout. **T (E2E, mobile + desktop):** the call to action reaches `/signup` and "Sign in" reaches `/login`; signed-in staff still see the page with a link to `/app`; no sideways scroll at 375 px; 44 px targets; one `h1` and ordered headings; review screenshots at 375/768/1440 in both modes.

### Phase 4 — Storefront & booking engine (Week 2, days 3–5)

**Decided (ADR-0010):** checkout works **without an account**: a guest gives an email (for tickets) and an M-Pesa phone number (for payment); tickets, a booking reference and a secret to reopen them are sent **by email, not SMS**. Accounts (ADR-0009) stay optional and are offered after purchase.

- [x] **4.1 Public storefront reads** (`/c/{slug}`: home, movie, screening; §41) — **T:** anonymous reads see only published data; unpublished is invisible; tenant A's slug never returns B's data.
- [x] **4.1b Cinema home page: sections and templates** (each cinema's landing page at its storefront address) — follows the theming rule: structure is code, content is data. A cinema's page is an ordered list of **typed sections** from a fixed set: hero (a featured movie or "now showing"), today's showtimes, now showing, coming soon, about (text + photos, reusing 3.4's upload rules), location and opening hours (address, map link), contact and social links, FAQ. Each section has typed, length-limited fields; tenants never supply HTML, CSS or JS (§55). **Templates** are named presets of section order and layout variant, e.g. *Marquee* (poster-led), *Schedule* (showtimes first) and *Compact* (a single scrolling list for small cinemas). An owner picks a template, shows, hides or reorders sections and fills in their text in the back-office (Settings › Home page) with a live preview; the page is stored as versioned data on the tenant subgraph like the theme (3.8), and rendered mobile-first with the cinema's theme. Sections with nothing to show (no screenings yet, no photos) collapse instead of showing empty boxes. **T:** the page-model validator rejects unknown section types, over-length or markup-bearing text and unknown template names; every template renders with sample data and with an empty cinema; tenant A's page settings never affect B (isolation); publish and roll back restore versions. **E2E (mobile + desktop):** switching template changes the storefront layout; hiding a section removes it; review screenshots of each template at 375/768/1440 in both modes.
- [x] **4.1c Storefront home design** (added 2026-10-01 after review: the 4.1b page worked but looked flat) — one visual structure for every cinema's home page, drawn in its theme, following the booking funnel (hero → pick a day → pick a showtime → seats): a header with the logo and links to What's on, Coming soon and Visit us; a hero with the featured movie on a **landscape backdrop** (an optional new movie image; a blurred, enlarged poster when there is none) and a Book tickets call; **showtimes by day** (a date strip, Today first, for the next 7 days; the chosen day lists its showtimes grouped by movie with posters — the 4.1b "today" section, now for every day); now showing as a poster row; coming soon as a row that swipes on phones; and a **Visit us** band that puts location and hours, contact and questions side by side. Templates vary the arrangement (Marquee: full-bleed hero; Schedule: date strip first; Compact: one column, slim hero). Movie pages get the same backdrop hero. Subtle motion only (a fade-in, off for reduced motion). Split: **4.1c-a** (server: backdrop upload/remove/public read; the programme by cinema day) and **4.1c-b** (the storefront design). **T:** backdrops are checked and re-encoded like posters and public only while their movie is; the days list covers the next 7 cinema days in its time zone with only published, not-started showtimes. **E2E (mobile + desktop):** picking a day shows that day's showtimes; the hero's Book tickets leads to the movie; phone checks; review screenshots of each template at 375/768/1440 in both modes.
- [x] **4.1d Storefront structure, tier A** (added 2026-10-02 from a review against common cinema-site practice: discover → venue → movie → date → showtime → book) — header navigation (Movies, Showtimes, Cinemas, Visit) with **search** (movie titles and venues across the programme) and a **Book tickets** call; on phones a compact header with a menu sheet. A **venue picker** for multi-venue cinemas that filters the page and is remembered on the device. A **quick-book** widget (venue → movie → date → time → the showtime's page) with empty and disabled states. Hero: Book tickets and View showtimes with rating, genre, runtime and language. Now showing cards with **filters** (genre, rating, language) and sort. Coming soon with a **release date** (a new optional movie field). A **Find a cinema** block (venue cards: address, map link, screens, what's on, book). Pages `/c/{slug}/movies` and `/c/{slug}/cinemas`. Footer columns (Movies, Cinemas, Help, Legal) linking only to pages that exist. Skeleton, empty and error states for each part. A unique document title per page. **T:** the release date is validated and public only with its movie; venue filtering and quick book only offer combinations that exist. **E2E (mobile + desktop):** search finds a movie and a venue and says when nothing matches; the venue picker filters and is remembered; quick book reaches the chosen showtime; filters narrow Now showing; the menu sheet works by keyboard; phone checks; review screenshots.
- [ ] **4.1e Storefront structure, tier B** (after the booking engine) — trailers (a link per movie; an accessible player with captions), screen and showtime **formats** (2D/3D/IMAX/VIP) as data, Offers and Events sections, "from KES …" prices on showtimes from the price list, and SEO structured data (Movie, MovieTheater, ScreeningEvent) with share metadata.
- [x] **4.2 Seat availability** — **T:** a lazily expired hold shows as AVAILABLE; BLOCKED/HOUSE are not sellable; the response carries text states (accessibility, §102).
- [x] **4.3 Seat holds** (§24, §25; one hold per seat is an atomic claim with the hold time as its TTL, ADR-0007) — **T:** hold/release/extend; per-customer cap; **concurrency: 50 parallel holds on one seat → exactly 1 succeeds**; overlapping multi-seat holds → no partial holds.
- [x] **4.4 Hold expiry sweeper** (`@schedule`) — **T:** idempotent when run twice (it runs on every replica); never releases `PAYMENT_PENDING` holds.
- [x] **4.5 Orders/bookings with price snapshot & idempotency** (§26, §27) — **T:** same idempotency key → same booking (including concurrently); the snapshot is unchanged after a price edit.
- [x] **4.6 Storefront UI: seat map & checkout shell (mobile-first)** — **T (E2E, mobile + desktop):** pick a screening → select 2 seats (tap on mobile, click/keyboard on desktop) → hold timer shows → proceed to pay. On mobile: the seat map fits the width and can be zoomed, and the sticky bottom bar shows the seats and total. Keyboard-only seat selection works on desktop. Decide on `[client.pwa]` here: **deferred to Phase 6** (2026-10-02), since its point is an offline ticket view and tickets arrive in 6.1.
- [x] **4.7 Load test (spike S5)** — **T:** 200 concurrent hold attempts on one screening: zero double-holds, p95 latency and 409-rate within the targets recorded in the S5 ADR. **Done (ADR-0014):** correctness holds (one winner per seat, the seat map agrees, no failures); latency targets are regression guards from the development machine's baseline; run with `scripts/load.sh`.

### Phase 5 — M-Pesa payments via Daraja (Week 3, days 1–3)

- [x] **5.1 `PaymentProvider` interface + simulator** — **T:** the simulator scripts success/fail/cancel/timeout/late-success; the payment state machine (§32) rejects invalid transitions.
- [x] **5.2 Daraja adapter** (OAuth token cache, STK push, STK query, C2B registration later) — **T:** HTTP-mocked contract tests from recorded sandbox fixtures; token refresh; timeouts/retries; no secrets in logs.
- [x] **5.3 `initiate_payment`** (§29) — **T:** creates a `PaymentIntent` + extends the hold to `PAYMENT_PENDING`; **a forced serialization replay still produces exactly one STK call** (`on_commit`/outbox); the idempotency key prevents a double initiate.
- [x] **5.4 Callback → receipt → verified finalize** (§33–§35) — **T:** the callback only stores a receipt; the worker verifies via STK query; finalize makes Payment SUCCESS + Booking CONFIRMED + SeatSlots SOLD + Tickets ISSUED atomically; **3 duplicate callbacks → one ticket set**; amount mismatch → `NEEDS_ATTENTION`; late success after release → `NEEDS_ATTENTION` + refund task.
- [x] **5.5 TIMEOUT/UNKNOWN resolver job + ledger entries** (§37, §124) — **T:** stuck intents are resolved via status query; ledger entries are append-only and balance per booking. An order nobody started paying by its `pay_by` (P4.5) is ended: its seats, its hold and their claims (seat, `order-hold`) are released, so PAYMENT_PENDING never sticks.
- [x] **5.6 Checkout UI** (enter phone → "check your phone" → live status) — **T (E2E, simulator, mobile + desktop):** success path shows the ticket; a failure releases the seats with a message. **Done as:** a failure shows its message and lets the visitor try again (the order keeps its seats until `pay_by`; the 5.5 resolver releases them after, tested there). The simulator gained test numbers (0700 000 001 fails, …002 cancels, …003 times out, …004 is refused) for browser tests and demos. The M-Pesa phone field uses `inputmode="tel"` and is validated inline.
- [x] **5.7 Daraja sandbox end-to-end** (nightly job + manual; callback via a Cloudflare Tunnel URL) — **✓** A real sandbox STK payment produces a ticket. **Built:** `scripts/sandbox.sh` (login, a KES 1 push, its status query; `DARAJA_RECORD=1` saves Safaricom's replies, redacted, as fixtures), the nightly **Daraja sandbox** workflow, and `docs/runbooks/daraja-sandbox.md` for the manual journey. **Done 2026-10-07:** a real KES 1 sandbox payment from a phone produced a ticket. Safaricom's callback didn't arrive in that run; the 5.5 resolver settled it from the status query after about 85 s.

### Phase 6 — Tickets, scanning, box office (Week 3, days 3–4)

- [ ] **6.1 Ticket issuance & QR** (§46) — **T:** the QR payload is an opaque HMAC-signed reference with no PII; a tampered signature is rejected; references are unique. **Built (ADR-0020):** references are 16 readable random characters, claimed for their ticket (the scanner's index in 6.2); the QR payload is `TKT1.<reference>.<HMAC>` with `AFRICINEMAS_TICKET_KEY`, and payments are refused without the key. The booked panel shows each ticket's QR code (`qrcode.react`), covered by the payment E2E.
- [ ] **6.2 Redemption** (§47) — **T:** valid → USED; second scan → `ALREADY_REDEEMED`; **concurrent double-scan → exactly one success**; wrong screening/tenant/voided/refunded are rejected; only usher-capable roles may scan. **Built (ADR-0021):** `redeem_ticket` takes a QR payload or a typed reference for the showtime being checked; an atomic claim makes one scan win. Added: the door window (from 2 hours before the start until the showtime ends: `too_early`, `showtime_over`), and `wrong_showtime` names the ticket's showtime.
- [x] **6.3 Customer tickets** (view, resend via `on_commit` email) — **T:** a customer sees only their own tickets; resend is rate-limited. **Split:** 6.3a, built (ADR-0022): the email at checkout, the private ticket link (`/c/<slug>/tickets/<token>`; whoever holds it sees the tickets, and nothing else does), the ticket email with QR images, queued and sent by a job (development outbox without SMTP), and resending, 3 times an hour, to the same or a corrected address. 6.3b, built (ADR-0023): "My tickets" for signed-in customers; a signed-in visitor's tickets are saved to their account by the page itself (`save_booking` proves the link), and `my_tickets` reads only the caller's own index, so a customer sees only their own tickets.
- [ ] **6.4 Web scanner page** (camera QR via an npm lib; manual entry fallback) — **T (E2E):** manual-entry redeem flow; the camera component is unit-tested with an injected decoder.
- [ ] **6.5 Box-office walk-in sale** (counter mode: cash or M-Pesa at the counter) — **T:** a cash sale creates a confirmed booking + ledger entry attributed to the agent; the agent can't sell for another venue.

### Phase 7 — Owner dashboard & audit (Week 3, day 5)

- [ ] **7.1 Reporting aggregates** (§76, §77) — **T:** against a fixture graph with known numbers: revenue, tickets sold, occupancy %, top movies, per-venue drill-down; refunds are subtracted.
- [ ] **7.2 Audit log** (§66, §67) — **T:** every sensitive endpoint emits exactly one `AuditEvent` (a registry-driven meta-test); owners can read but not delete audit events.
- [ ] **7.3 Dashboard UI** (charts) — **T (E2E, mobile + desktop):** after a seeded sale the dashboard shows the matching totals. On mobile, KPI tiles stack and charts stay legible.

### Phase 8 — AI features with `by llm` (Gemini) (Week 4, days 1–2)

- [ ] **8.1 LLM plumbing** (adds `[byllm.model]` for Gemini with the key from the environment, never a `${VAR}` placeholder (JI-015), and confirms which env var the provider reads, `GEMINI_API_KEY` or `GOOGLE_API_KEY`) — **T:** MockLLM harness; timeout and error → graceful fallback; prompts contain tenant-scoped data only, never customer PII.
- [ ] **8.2 Synopsis & promo-copy generator** (owner) — **T:** structured `obj` output (tagline, synopsis, social post) respects length limits.
- [ ] **8.3 "What should I watch tonight?"** (customer) — **T:** recommendations only reference real, published, on-sale screenings of *this* tenant; hallucinated IDs are filtered out.
- [ ] **8.4 Natural-language showtime search** — **T:** text → typed `ScreeningFilter` obj → deterministic graph query; unsafe or empty parses fall back to a keyword search.
- [ ] **8.5 AI brand-theme generator** (replaces the dashboard narrative) — the tenant uploads logo/brand photos → dominant colours are **extracted deterministically** (clustering) → Gemini `by llm` (multimodal) returns **3 typed `ThemeProposal`s** (colour roles, allowlisted fonts, radius, mood name) → each goes through `repair_theme` + `validate_theme` → live storefront preview → choose/tweak → publish as a new theme version (3.8). **T:** MockLLM returns proposals, including deliberately bad ones → every proposal shown to the tenant passes validation; a failure or timeout falls back to the default theme; only allowlisted fonts are accepted; the images are never echoed back into prompts beyond the upload.
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

- [ ] **11.1 Security pass** — **T:** the full isolation suite is green; production-config assertions; CSP/security headers at the edge; rate limits on sign-in and hold/pay/scan (Jac 0.37.18 limits `/user/register` only, not `/user/login`, so password guessing is unthrottled until then); the threat-model items from §131 relevant to the MVP each have a test.
- [ ] **11.1b Claim reconciliation job** (`@schedule`, ADR-0007) — **T:** a committed tenant whose slug claim lapsed (server died before `on_commit`) gets it re-claimed; a claim held by no committed tenant is released; the same for venue and auditorium name claims (P3.1): a committed node's name is re-claimed, a name whose node was deleted or renamed is released; media files no movie references (a crash mid-upload, ADR-0011) are deleted; running it twice changes nothing.
- [ ] **11.1c Faster holds under load** (ADR-0014) — holds that never touch the graph: the seat map reads holds from the seat claims (one query per showtime), so a hold writes no node. **T:** `scripts/load.sh` passes with lower targets, re-measured with one and with several workers (`jac start --workers N`).
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
