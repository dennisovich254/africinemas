#!/usr/bin/env bash
# Self-test for the pre-commit hooks (plan P0.4).
# Builds a throwaway git repo with this project's hook config and asserts that
# each gate REJECTS bad input and ACCEPTS clean input. Exits non-zero on any miss.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d -t africinemas-hooks-XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

failures=0
expect() {  # expect <pass|fail> <description> <command...>
    local want="$1" desc="$2"; shift 2
    if "$@" >"$WORK/.last.log" 2>&1; then got=pass; else got=fail; fi
    if [[ "$got" == "$want" ]]; then printf '  ok    %-52s (%s as expected)\n' "$desc" "$got"
    else printf '  MISS  %-52s (wanted %s, got %s)\n' "$desc" "$want" "$got"; sed 's/^/        /' "$WORK/.last.log" | tail -8; failures=$((failures + 1)); fi
}

[[ -f "$ROOT/.pre-commit-config.yaml" ]] || { echo "  MISS  .pre-commit-config.yaml not found"; exit 1; }

# Throwaway repo carrying the real hook config and helper scripts.
cd "$WORK" && git init -q -b main && git config user.email selftest@example.com && git config user.name selftest
cp "$ROOT/.pre-commit-config.yaml" . && cp -r "$ROOT/scripts" . && printf '[project]\nname = "hooks-selftest"\n' > jac.toml
git add -A && git -c core.hooksPath=/dev/null commit -q -m "chore: seed"
git switch -q -c feat/selftest

run_hook() { pre-commit run "$1" --files "${@:2}"; }

# 1. Formatting
printf 'def   f->int{return 1;}\n' > badfmt.jac
printf 'def f -> int {\n    return 1;\n}\n' > clean.jac
git add badfmt.jac clean.jac
expect fail "jac-fmt rejects a badly formatted .jac file"   run_hook jac-fmt badfmt.jac
expect pass "jac-fmt accepts a formatted .jac file"         run_hook jac-fmt clean.jac

# 2. Lint (jac check --lint exits 0 on findings: JI-010, so our wrapper must fail)
printf 'def f() -> int {\n    return 1;\n}\n' > lintbad.jac
git add lintbad.jac
expect fail "jac-lint rejects a lint violation"             run_hook jac-lint lintbad.jac
expect pass "jac-lint accepts clean code"                   run_hook jac-lint clean.jac

# 3. Secrets (built at runtime so this file itself never contains one)
pk_header="-----BEGIN RSA ""PRIVATE KEY-----"
printf '%s\nMIIEpAIBAAKCAQEAselftestselftest\n' "$pk_header" > id_fake
token_prefix="gh""p_"; printf 'GITHUB_TOKEN = "%s%s"\n' "$token_prefix" "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8" > leaked.py
git add id_fake leaked.py
expect fail "detect-private-key rejects a private key"      run_hook detect-private-key id_fake
expect fail "gitleaks rejects a staged GitHub token"        run_hook gitleaks-system leaked.py
git rm -q --cached id_fake leaked.py && rm -f id_fake leaked.py
expect pass "gitleaks accepts a tree without secrets"       run_hook gitleaks-system clean.jac

# 4. Commit messages (Conventional Commits)
printf 'update stuff\n' > bad_msg; printf 'feat(p0.4): add pre-commit hooks\n' > good_msg
expect fail "commit-msg rejects 'update stuff'"             pre-commit run conventional-pre-commit --hook-stage commit-msg --commit-msg-filename bad_msg
expect pass "commit-msg accepts 'feat(p0.4): ...'"          pre-commit run conventional-pre-commit --hook-stage commit-msg --commit-msg-filename good_msg

# 5. No direct commits to main
git switch -q main
expect fail "no-commit-to-branch blocks commits on main"    run_hook no-commit-to-branch clean.jac
git switch -q feat/selftest
expect pass "no-commit-to-branch allows feature branches"   run_hook no-commit-to-branch clean.jac

# 6. Warning ratchet (runs against the real project)
cd "$ROOT"
expect fail "warning ratchet fails when count > baseline"   env WARNING_BASELINE=0 scripts/check_warnings.sh
expect pass "warning ratchet passes at the committed baseline" scripts/check_warnings.sh

echo
if (( failures > 0 )); then echo "$failures hook self-test(s) failed."; exit 1; fi
echo "All hook self-tests passed."
