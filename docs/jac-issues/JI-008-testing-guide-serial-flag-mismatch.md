# JI-008: `jac-testing` guide says no CLI flag forces serial, but `-j 0` exists

- **Version:** jaclang 0.37.18 (bundled guide `jac guide jac-testing`)
- **Found:** 2026-09-26, P0.3
- **Status:** open (docs)

## Mismatch
- Guide: *"no CLI flag forces serial; set `JAC_TEST_JOBS=0` in the environment or `test_jobs = "0"` under `[dev]`"*.
- `jac test --help`: *"-j, --jobs JOBS: Worker processes: a count, 'auto' (one per core, memory-budgeted) or 0 for serial"*.

The `--help` output comes from the installed binary, so we follow it.
