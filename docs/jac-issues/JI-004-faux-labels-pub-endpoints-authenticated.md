# JI-004: `jac run --faux` lists `def:pub` functions under "FUNCTIONS (Authenticated)"

- **Version:** jaclang 0.37.18
- **Found:** 2026-09-26, P0.2
- **Status:** open (maybe a labelling/heading issue only)

## Behaviour
`core/health.jac` declares `def:pub app_info -> AppInfo`. `jac run --faux web` prints it under `FUNCTIONS (Authenticated)`. A real server answers `POST /function/app_info` with **HTTP 200 and no token** (verified with `curl`), so the endpoint is public, as `:pub` intends.

## Impact / workaround
Misleading for security review only. Don't use `--faux` headings to decide auth. The isolation tests (plan P2.4) are the source of truth.
