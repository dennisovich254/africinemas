# JI-001: `jac test` may treat a missing in-project module as an optional dependency

- **Version:** jaclang 0.37.18, Linux x86_64 (WSL2)
- **Found:** 2026-09-26, P0.3
- **Status:** open. Discord message drafted; behaviour for *third-party* optional deps is intentional (release notes).

## Behaviour
A test file importing a module that doesn't exist, under a local package other than `tests/`, is reported **SKIPPED** and `jac test` exits **0**. With `JAC_TEST_STRICT=1` it's an ERROR (exit 1).

## Repro
```bash
mkdir -p skip-repro/mylib skip-repro/checks && cd skip-repro
printf '[project]\nname = "skiprepro"\n' > jac.toml
printf 'def one -> int { return 1; }\n' > mylib/real.jac
printf 'import from mylib.missing { one }\n\ntest "never runs" {\n    assert one() == 999;\n}\n' > checks/broken_tests.jac
jac test -d checks -v; echo "exit: $?"                    # SKIPPED, exit 0
JAC_TEST_STRICT=1 jac test -d checks -v; echo "exit: $?"  # ERROR, exit 1
```

## Analysis
`_optional_dep_gap()` (`jaclang/testing/impl/test_runner.impl.jac`, ~L199) returns the top-level name of any `ModuleNotFoundError` unless it's `jaclang`, `tests` or stdlib. `run_file` (~L698) then skips unless `strict_mode()` is on. The release notes (jaclang.md, ~L506) document the skip for *missing optional dependencies* and recommend `JAC_TEST_STRICT=1` for CI. What's unclear is whether in-project packages are meant to hit this path.

## Workaround (in place)
`scripts/test.sh` exports `JAC_TEST_STRICT=1`. It's the only switch: an environment variable, with no CLI flag or `jac.toml` key.
