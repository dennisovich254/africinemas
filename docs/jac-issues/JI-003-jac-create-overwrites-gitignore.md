# JI-003: `jac create` in a non-empty directory overwrites an existing `.gitignore`

- **Version:** jaclang 0.37.18
- **Found:** 2026-09-26, P0.2
- **Status:** open

## Behaviour
Running `jac create --use jac-shadcn` (no name, so it initializes the cwd) in a repo that already had a `.gitignore` (listing `.env`, `.mcp.json`, `resources/`) replaced it with the template's two lines (`.jac/`, `node_modules/`). `git status` then showed `.env` and `.mcp.json` as untracked, committable files. The scaffold printed `✔ .gitignore` with no warning.

## Workaround (in place)
Back up `.gitignore` before `jac create` and restore or merge it afterwards. We caught this before staging anything.

## Possible improvement (suggestion)
Merge (append missing lines) instead of overwriting, or refuse and warn when the file exists.
