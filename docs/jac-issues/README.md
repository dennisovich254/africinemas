# Jac stack issues log

Problems we hit in the Jac/Jaseci toolchain itself (not in AfriCinemas code): bugs, CLI quirks,
docs-vs-behaviour mismatches and platform limitations. Each entry is verified (repro, exit code, or
source/`--help` output) before it's logged. The wording is tentative where the behaviour may be intended.

**Format:** one file per issue, `JI-NNN-short-slug.md`, with version, repro, expected vs actual,
workaround, and status. Status values: `open` · `reported` (link) · `answered` · `fixed in <version>` · `wontfix/intended`.

| ID | Title | Area | Severity for us | Status |
| --- | --- | --- | --- | --- |
| [JI-001](JI-001-test-runner-skips-missing-local-module.md) | `jac test` may treat a missing in-project module as an optional dependency (skip, exit 0) | testing | High (silent coverage loss) | open, Discord draft ready |
| [JI-002](JI-002-bundled-bun-requires-avx2.md) | Bundled bun crashes with "Illegal instruction" on CPUs without AVX2 | toolchain | High on our dev box (workaround in place) | open |
| [JI-003](JI-003-jac-create-overwrites-gitignore.md) | `jac create` in a non-empty directory overwrites an existing `.gitignore` | scaffold | High (can expose `.env`) | open |
| [JI-004](JI-004-faux-labels-pub-endpoints-authenticated.md) | `jac run --faux` lists `def:pub` functions under "FUNCTIONS (Authenticated)" | server/CLI | Low (misleading output) | open |
| [JI-005](JI-005-desktop-client-build-needs-sudo.md) | `jac build desktop --as client` still provisions the native toolchain via `sudo -n apt-get` | desktop | Medium (local builds blocked) | open |
| [JI-006](JI-006-dev-run-ignores-port.md) | `jac run <web-app>` (dev mode) appears to ignore `--port` | CLI | Low | open |
| [JI-007](JI-007-jac-test-positional-directory-collects-nothing.md) | `jac test <dir>` (positional) collects nothing; only `-d <dir>` works | testing | Low (fails loudly, exit 5) | open |
| [JI-008](JI-008-testing-guide-serial-flag-mismatch.md) | `jac-testing` guide says no CLI flag forces serial, but `-j 0` exists | docs | Low | open |
| [JI-009](JI-009-scaffold-templates-not-lint-clean.md) | Freshly scaffolded templates produce ~130 `jac check` warnings | scaffold | Low (noise; ratcheted) | open |
| [JI-010](JI-010-lint-findings-exit-zero.md) | `jac check --lint` exits 0 when it reports lint violations | lint/CI | Medium (hooks wouldn't block) | open |
