# JI-002: Bundled bun crashes with "Illegal instruction" on CPUs without AVX2

- **Version:** jaclang 0.37.18 (bundled bun at `~/.cache/jac/rt/<hash>/site/jaclang/client/_bun/bun`)
- **Found:** 2026-09-26, P0.2
- **Status:** open

## Behaviour
On an Intel Celeron N4020 (no AVX/AVX2/BMI2, has SSE4.2), `jac install` fails with only `bun install failed after 0.3s`. Running the bundled bun directly shows `Illegal instruction` (exit 132). The Vite dev server also fails to start, with just "Vite dev server failed to start".

## Workaround (in place)
Install bun's official **baseline** build (`bun-linux-x64-baseline.zip`, checksum-verified) and `export JAC_BUN=$HOME/.local/opt/bun-baseline/bun`. `scripts/doctor.sh` detects the problem and prints this fix.

## Possible improvement (suggestion)
Jac could detect a missing AVX2 and use or ship the baseline build, or at least surface bun's exit signal instead of a bare "install failed".
