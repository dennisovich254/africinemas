# ADR-0013: A cinema's branding is versioned token data, published to its storefront

- **Status:** Accepted
- **Date:** 2026-09-29
- **Sub-phase:** P3.8a
- **Code:** `core/theming/branding.jac`, `core/theming/branding_api.jac`, `core/theming/models.jac`, `core/catalog/storefront.jac`, `core/catalog/poster.jac`
- **Tests:** `tests/unit/branding_tests.jac`, `tests/integration/branding_tests.jac`, `tests/isolation/`

## Context
The theming model (plan §4, 2026-09-27) makes a cinema's look data, not code: typed colour tokens, allowlisted fonts and a radius, checked for WCAG AA in both modes (P0.8a). Plan 3.8 lets a cinema pick and publish its own theme and logo, and roll back. Visitors read the storefront anonymously, on the shared guest graph (ADR-0012).

## Decision
1. **Draft, then publish.** A cinema's one `Branding` node (recorded on `Tenant.branding_id`) holds the draft theme and logo. Publishing copies them into a new, numbered `ThemeVersion`, which never changes, and onto the cinema's `Storefront`. Publishing what the storefront already shows is refused.
2. **Rolling back publishes again.** Rolling back to version *n* publishes *n*'s theme and logo as the next version and makes them the draft. History only grows, so it always shows what was public when.
3. **Only token values are stored.** `parse_theme` accepts exactly a theme's fields: every role, in both modes, as `#RRGGBB`, and fonts and radius from the allowlists. `public_branding` checks the theme again before building CSS from it.
4. **Unreadable colours are repaired on save, and reported** (the owner's choice, 2026-09-29). The save stores `repair_theme`'s result and returns each colour it changed (mode, role, before, after), so the UI can say so. An owner is never stuck, and nothing unreadable is stored.
5. **The logo goes through the poster checks** (§56): type and signature, size, dimensions, decoded and re-encoded as a clean WebP. It is fitted into 512 × 512 and keeps its transparency. It is stored inline as base64 on the draft, each version and the storefront, not in the media store, so a version is self-contained and rolling back needs no file bookkeeping. At 512 px a WebP logo is tens of kilobytes.
6. **Concurrency:** the first save sets `Tenant.branding_id`, and every publish raises `Branding.version`. Concurrent requests write the same record, so the database lets one through and re-runs the others (JI-031), which then see its result.

## Consequences
- The storefront shows the platform default until a cinema publishes, and `public_branding` returns version 0.
- The back-office keeps the platform look and uses only the cinema's logo and accent (3.8b).
- Storing logos inline repeats them per version. If logos grow or versions pile up, move them to the media store with reference counting.
