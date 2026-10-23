# ADR-0059: The platform's own audit log

- **Status:** Accepted
- **Date:** 2026-10-23
- **Sub-phase:** P13.3
- **Code:** `core/platform/audit_api.jac` (`platform_audit_log`, `platform_signed_in`), `core/audit/log.jac` (`platform_record`, `platform_events`), `core/platform/staff_api.jac` (refused attempts), `web/platform/PlatformAuditPage.jac`, `web/platform/PlatformAuthPages.jac` (the sign-in report)
- **Tests:** `tests/integration/platform_audit_tests.jac`, `e2e/platform_audit_tests.jac`

## Context
Platform actions have gone to their own collection since P13.1 (ADR-0055), but nobody could read them. The team's work (staff changes now; reviews, suspensions and support replies from Phase 14 and 13.5) needs a record anyone accountable can check: who did what, when, to whom or which cinema, and what was refused.

## Decision
1. **One log, read like the cinema's** (ADR-0027, improvements #12). It's newest first and paged by the last event shown, so new events don't shift the pages. It's narrowed by one action and by a search. The search here also matches what an event was done to (a platform member's email). A cinema filter keeps the events about one cinema (`?cinema=<slug>`, linked from its directory page).
2. **Super admins only** (`platform.audit`). It's the record of what the team does, so reviewers and support don't read each other's trail.
3. **Refused attempts are recorded**, including ones refused before any work: a cinema account trying a platform action, or a reviewer trying to manage staff. They're recorded under the caller's root, with no email when it isn't a platform account. Anyone signed in could add refused events, but each one costs a signed-in request, and the events are what an investigation would want.
4. **Sign-ins are reported by the sign-in and join pages** (`platform_signed_in`), because Jac's own sign-in runs no code of ours. So a wrong password isn't in this log. Account lockout and failed-sign-in alerts belong to threat model 3.1.
5. **Nothing changes or deletes an event.** Only `core/audit/log.jac` writes the collection, and the endpoints only read it. The cinemas directory's history reads the same events, by cinema.

## Consequences
- Phase 14's reviews and suspensions only need to record with `resource_type` "cinema" and the cinema's id. They then show in this log, under the cinema filter, and in the cinema's history.
- Reads (opening a cinema's page) aren't recorded. If the team ever handles customer data (13.5's support requests), reading it should be.
