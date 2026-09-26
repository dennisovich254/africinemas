#!/usr/bin/env bash
# Toolchain doctor for AfriCinemas.
# Verifies every tool the dev workflow depends on. Exits non-zero if any check fails.
# Usage: scripts/doctor.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

if [[ -t 1 ]]; then GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; RESET=$'\e[0m'; else GREEN=""; RED=""; DIM=""; RESET=""; fi
failures=0

pass() { printf '%s  PASS%s  %s\n' "$GREEN" "$RESET" "$1"; }
fail() { printf '%s  FAIL%s  %s\n' "$RED" "$RESET" "$1"; [[ -n "${2:-}" ]] && printf '        %sfix: %s%s\n' "$DIM" "$2" "$RESET"; failures=$((failures + 1)); }

# 1. Jac installed at the pinned version (.jac-version is the single source of truth)
pinned="$(tr -d '[:space:]' < .jac-version 2>/dev/null)"
if [[ -z "$pinned" ]]; then
    fail "pinned Jac version in .jac-version" "create .jac-version containing e.g. 0.37.18"
elif ! command -v jac >/dev/null 2>&1; then
    fail "jac on PATH" "install Jac $pinned and add it to PATH"
else
    actual="$(jac --version 2>/dev/null | awk '{print $2}')"
    if [[ "$actual" == "$pinned" ]]; then pass "jac $actual (pinned $pinned)"
    else fail "jac version $actual != pinned $pinned" "install Jac $pinned, or bump .jac-version in a PR"; fi
fi

# 2. Jac MCP server answers an MCP initialize request
if command -v jac >/dev/null 2>&1; then
    init='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"doctor","version":"0"}}}'
    # Capture first, then match: piping into `grep -q` would SIGPIPE jac and fail under pipefail.
    mcp_reply="$(printf '%s\n' "$init" | timeout 30 jac mcp 2>/dev/null)"
    if [[ "$mcp_reply" == *'"serverInfo"'* ]]; then
        pass "jac mcp responds to initialize"
    else
        fail "jac mcp did not answer within 30s" "run 'jac mcp' manually to see the error"
    fi
fi

# 1b. jac.toml pins the same Jac version as .jac-version
if [[ -f jac.toml && -n "$pinned" ]]; then
    toml_pin="$(sed -n 's/^jac-version *= *"==\{0,1\}\([^"]*\)".*/\1/p' jac.toml | head -1)"
    if [[ "$toml_pin" == "$pinned" ]]; then pass "jac.toml jac-version matches ($toml_pin)"
    else fail "jac.toml jac-version '$toml_pin' != .jac-version '$pinned'" "set jac-version = \"==$pinned\" under [project] in jac.toml"; fi
fi

# 2b. The bun that Jac uses for client builds runs on this CPU.
#     Jac's bundled bun needs AVX2; older CPUs (e.g. Celeron N4020) need bun's "baseline" build via JAC_BUN.
if [[ -n "${JAC_BUN:-}" ]]; then
    bun_bin="$JAC_BUN"; bun_src="JAC_BUN"
else
    bun_bin="$(ls -t "$HOME"/.cache/jac/rt/*/site/jaclang/client/_bun/bun 2>/dev/null | head -1)"; bun_src="bundled"
fi
if [[ -z "$bun_bin" ]]; then
    fail "no bun found for Jac client builds" "run 'jac install' once so Jac unpacks its bundled bun"
elif bun_ver="$("$bun_bin" --version 2>/dev/null)"; then
    pass "bun $bun_ver runs ($bun_src)"
else
    fail "bun ($bun_src: $bun_bin) does not run on this CPU" "install bun's baseline build (github.com/oven-sh/bun/releases: bun-linux-x64-baseline.zip) and export JAC_BUN=/path/to/bun"
fi

# 3. Python 3.10+ (pre-commit hooks and the ui-ux-pro-max skill scripts)
if python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
    pass "python3 $(python3 -c 'import platform; print(platform.python_version())')"
else
    fail "python3 >= 3.10" "install Python 3.10 or newer"
fi

# 4. Git identity and remote
name="$(git config user.name 2>/dev/null)"; email="$(git config user.email 2>/dev/null)"
if [[ -n "$name" && -n "$email" ]]; then pass "git identity: $name <$email>"
else fail "git user.name / user.email not set" "git config --global user.name 'Your Name' && git config --global user.email you@example.com"; fi

if git remote get-url origin >/dev/null 2>&1; then pass "git remote origin: $(git remote get-url origin)"
else fail "git remote 'origin' missing" "git remote add origin https://github.com/<owner>/africinemas.git"; fi

# 5. Secrets file is never committable
if [[ ! -e .env ]] || git check-ignore -q .env; then pass ".env is git-ignored"
else fail ".env exists but is NOT git-ignored" "add .env to .gitignore"; fi

# 6. pre-commit
if command -v pre-commit >/dev/null 2>&1; then pass "pre-commit $(pre-commit --version | awk '{print $2}')"
else fail "pre-commit not installed" "uv tool install pre-commit   (uv: github.com/astral-sh/uv/releases)"; fi

# 7. GitHub CLI, authenticated (needed for PRs and pushing)
if ! command -v gh >/dev/null 2>&1; then
    fail "gh (GitHub CLI) not installed" "download gh_<ver>_linux_amd64.tar.gz from github.com/cli/cli/releases, verify its checksum, copy bin/gh to ~/.local/bin"
elif gh auth status >/dev/null 2>&1; then
    pass "gh $(gh --version | head -1 | awk '{print $3}') authenticated"
else
    fail "gh installed but not authenticated" "gh auth login && gh auth setup-git"
fi

echo
if (( failures > 0 )); then
    printf '%s%d check(s) failed.%s\n' "$RED" "$failures" "$RESET"
    exit 1
fi
printf '%sAll checks passed.%s\n' "$GREEN" "$RESET"
