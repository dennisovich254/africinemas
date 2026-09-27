# JI-013: In a workspace, `jac build web` outputs to `.jac/client/web/dist`, not `.jac/client/dist`

- **Version:** jaclang 0.37.18
- **Found:** 2026-09-27, P0.5 (first CI run)
- **Status:** open (docs)

## Mismatch
- `jac-client` reference (build kinds table): `web-app` → `jac build web` → output `.jac/client/dist/`.
- Actual, in a workspace with `[apps.web]`: the build succeeded and the bundle was at **`.jac/client/web/dist`** (one directory per app). Our CI artifact upload of `.jac/client/dist/` found no files.

The docs probably describe the single-app layout. It isn't clear to me whether the per-app path is stable or documented elsewhere.

## Workaround (in place)
CI uploads `.jac/client/web/dist/`.
