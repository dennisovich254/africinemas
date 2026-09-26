# Provenance

- Upstream: https://github.com/nextlevelbuilder/ui-ux-pro-max-skill (MIT, see LICENSE)
- Path in upstream: `.claude/skills/ui-ux-pro-max/`
- Pinned commit: `d62fe62f88acb6755d2e5819a1b1e19eb447a8f1` (reviewed 2026-09-26)
- Review: the Python scripts only search the bundled local CSV/JSON data. They make no network calls and run no subprocesses. They write files only with `--persist` (to `design-system/<slug>/` under `--output-dir`).

## Local modifications
- `SKILL.md`: script paths changed from `${CLAUDE_PLUGIN_ROOT}/.claude/skills/ui-ux-pro-max/...` to the project-relative `.claude/skills/ui-ux-pro-max/...`, because `CLAUDE_PLUGIN_ROOT` is only set for plugin installs. Run the commands from the repo root.

## Not installed (deliberately)
The upstream companion skills `design`, `brand`, `banner-design`, `slides`, `design-system` and `ui-styling` are not included. They call external image APIs (Gemini/MuAPI) or run Node/npx scripts that write into the project, and `ui-styling` drives the upstream shadcn CLI, which would conflict with jac-shadcn (`jac install --shadcn`).

To update: re-clone upstream, diff against this folder, review, and re-apply the path patch.
