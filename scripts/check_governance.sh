#!/usr/bin/env bash
# Governance self-check (plan P0.6): required repo files exist and are meaningful.
# Never prints secret VALUES: .env is only read for variable NAMES.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
failures=0
ok()   { printf '  ok    %s\n' "$1"; }
miss() { printf '  MISS  %s\n' "$1"; failures=$((failures + 1)); }
has()  { [[ -s "$1" ]] && ok "$1 exists" || miss "$1 missing or empty"; }
contains() { grep -qF -- "$2" "$1" 2>/dev/null && ok "$1 mentions: $2" || miss "$1 should mention: $2"; }

for f in .github/CODEOWNERS .github/PULL_REQUEST_TEMPLATE.md .github/dependabot.yml \
         .github/ISSUE_TEMPLATE/bug_report.yml .github/ISSUE_TEMPLATE/feature_request.yml \
         .github/ISSUE_TEMPLATE/config.yml CONTRIBUTING.md SECURITY.md .editorconfig \
         .env.example docs/architecture.md; do has "$f"; done

# PR template: a summary and, for UI changes, screenshots. The Definition of Done lives in
# the plan (docs/IMPLEMENTATION_PLAN.md), not in PR descriptions (owner's decision).
for item in "## Summary" "375 px · 768 px · 1440 px"; do
    contains .github/PULL_REQUEST_TEMPLATE.md "$item"
done

# CONTRIBUTING explains the workflow and setup
for item in "scripts/doctor.sh" "pre-commit install" "scripts/install_jac.sh" "RED" "GREEN" "Conventional Commits" "squash"; do
    contains CONTRIBUTING.md "$item"
done

# .env.example: every variable name used in .env and referenced in jac.toml is documented,
# and no value is filled in (names and comments only).
names() { grep -E '^\s*(export\s+)?[A-Za-z_][A-Za-z0-9_]*\s*=' "$1" 2>/dev/null | sed -E 's/^\s*(export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=.*/\2/' | sort -u; }
example_names="$(names .env.example)"
required="$( { [[ -f .env ]] && names .env; grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*' jac.toml | tr -d '${'; } | sort -u)"
for v in $required; do
    grep -qx "$v" <<<"$example_names" && ok ".env.example documents $v" || miss ".env.example is missing $v"
done
if grep -E '^\s*(export\s+)?[A-Za-z_][A-Za-z0-9_]*\s*=\s*[^[:space:]#]' .env.example >/dev/null 2>&1; then
    miss ".env.example must not contain values (found a non-empty assignment)"
else
    ok ".env.example has names only, no values"
fi

# Secrets stay out of git
for f in .env .mcp.json .claude/x resources/x; do
    git check-ignore -q "$f" && ok "$f is git-ignored" || miss "$f is NOT git-ignored"
done

# Dependabot watches the pinned GitHub Actions
contains .github/dependabot.yml "package-ecosystem: github-actions"

echo
if (( failures > 0 )); then echo "$failures governance check(s) failed."; exit 1; fi
echo "All governance checks passed."
