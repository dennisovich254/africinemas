## Summary
<!-- Which sub-phase from docs/IMPLEMENTATION_PLAN.md (e.g. P2.3), and what changed. -->

## TDD record
- **RED:** <!-- the tests you wrote first and how they failed -->
- **GREEN:** <!-- what made them pass -->

## Definition of Done
- [ ] Tests written first (RED), now passing, with no regressions (`scripts/test.sh`)
- [ ] `jac fmt --check`, `scripts/jac_lint.sh` and `scripts/check_warnings.sh` are clean
- [ ] New endpoints are in the tenant-isolation registry with cross-tenant tests
- [ ] New external side effects go through `on_commit` or the outbox, with a replay test
- [ ] UI changes: Playwright happy path on mobile + desktop; screenshots at 375 / 768 / 1440 px below
- [ ] Plan checkbox ticked; ADR added if a decision was made
- [ ] Any Jac-stack problem found is logged in `docs/jac-issues/`

## Screenshots (UI changes only)
<!-- 375 px · 768 px · 1440 px -->
