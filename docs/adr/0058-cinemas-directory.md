# ADR-0058: The platform's cinemas directory

- **Status:** Accepted
- **Date:** 2026-10-23
- **Sub-phase:** P13.2
- **Code:** `core/platform/cinemas_api.jac` (`platform_cinemas`, `platform_cinema`), `web/platform/CinemasPages.jac`, `web/platform/PlatformConsole.jac` (the Cinemas section)
- **Tests:** `tests/integration/platform_cinemas_tests.jac`, `tests/isolation/registry.jac` (the "platform" scope), `e2e/platform_cinemas_tests.jac`

## Context
AfriCinemas' team needs to see every cinema on the platform. Who it is, who owns it, what state it's in and how it's doing come first, before reviews (Phase 14) and support (13.5) can be done. A cinema's customers are the cinema's, not ours (Phase 13's rule), so the team mustn't see them.

## Decision
1. **Every platform role reads it** (`platform.read`), and it changes nothing. Reviewers and support need it as much as super admins do.
2. **The list is every cinema that finished signing up**, found through the slug registry. A slug held for a sign-up still in progress names no cinema yet, so it's left out. Cinemas are newest first, 20 a page (at most 50), searched by name, slug or an owner's email, and filtered by state. State names are in plain words: "Setting up", "Ready to go live", "Active", "Suspended", "Closing", "Deleted".
3. **Owners are the emails they signed in with**, from the cinema's own staff records. A cinema's records are read as its principal, as its own reports read them, and the figures come from the same records as its sales report: tickets sold and net takings so far.
4. **Counts only, never customers.** A cinema's page has its details, owners, staff count, venues and screens, and its figures. It never has a customer's name, phone or email, and the tests check that.
5. **The history is the sign-up, then the platform's own actions on the cinema**, from the platform audit log. Until Phase 14 adds reviews and suspensions, that's the sign-up alone.

## Consequences
- The search reads every cinema on each request. That's fine for hundreds of cinemas. For thousands, the directory would need an index of its own (a row per cinema, kept as cinemas change).
- The overview figures (13.4) can reuse the same records.
