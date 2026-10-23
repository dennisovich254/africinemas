# Jac issues: where we stopped (2026-10-21)

Paused to get back to AfriCinemas. This is the state to resume from.

## Done

- **Ranked the log by severity.** Tier 1: JI-015, JI-042, JI-038, JI-020, JI-024, JI-014, JI-003, JI-023, JI-043.
- **Re-checked tier 1 on jac 0.38.0** (released 2026-10-19):
  - **Still hold:** JI-015, JI-042 (worse, see below), JI-038, JI-020, JI-024, JI-014, JI-003.
  - **JI-023:** partly fixed.
  - **JI-043:** looks fixed.
- **JI-015 reported:** [jaseci-labs/jac#10277](https://github.com/jaseci-labs/jac/issues/10277).
  - Upstream, #8773 was closed by the stale bot. #9350 added a check, but only on deploy.
  - The issue proposes failing in `ServeSettings.validate` when a security setting still reads an unset `${VAR}`.
  - Repro project: `~/ji015-repro` (README with steps; `check_secret.py` checks only the user's own token).
- **JI-042 reported:** [jaseci-labs/jac#10280](https://github.com/jaseci-labs/jac/issues/10280). No earlier issue or PR; the related ones are #8711, #9044/#9069, #9878 and #9914.
  - Repro project: `~/ji042-repro` (README with steps).
  - The mechanism is corrected from the 0.37.18 entry; see the next section.

## JI-042, corrected mechanism (0.38.0)

Verified with a step trace on one worker:

1. The first run of the unit is read-only.
2. A write before `commit()` is **committed**: `_begin_writable` opens a SERIALIZABLE transaction when none is open, and skips the `_ro_units` check.
3. The write after `commit()` raises `ReadOnlyRetry` at unit exit. Only that write is rolled back.
4. The whole unit re-runs, so everything before `commit()` happens twice.

The writer mark is per process and expires after 300 s. So the double count hits the first call on each worker, and again after the TTL; it does not hit every call. 0.38.0 starts one worker per core, which makes it hit more often than on 0.37.x.

Workaround: `JAC_DB_RO_UNITS=0`, or no write after a mid-unit `commit()`.

## Found during the 0.38.0 upgrade, not yet logged

- **JI-002 (bundled bun needs AVX2) still holds on 0.38.0.** Vite died with exit 132 and jac printed only "Vite dev server failed to start".
  - Workaround in place: the bun 1.3.11 `linux-x64-baseline` build (checksum verified) replaces `~/.cache/jac/rt/c7d0c500758f2d8a/site/jaclang/client/_bun/bun`.
  - The original is kept as `bun.avx2-original`.
  - **Every Jac upgrade needs this swap again.**
- **Candidate JI-050:** the checker rejects a lambda for Pillow's `Image.point(lut=...)` (E1053, "type _SpecialForm"); the union includes `NumpyArray`. Worked around in `core/theming/logo.jac` with 256-entry lookup lists.
- **Candidate JI-051:** a Jac-level `import litellm;` costs about 5 to 7 minutes on **every** `jac run --dev` and `jac check`. The interface is rebuilt each time and never cached. Worked around in `core/agent/agent.jac` by importing litellm inside a `::py::` block.
- **Candidate JI-052 (high):** in 0.38.0 every `by` function's semantic info has an empty `params` list. byLLM's `MTRuntime.factory` then raises `IndexError` (`params[idx]`) before calling the model, with a real model or `MockLLM`, so the booking chat always fell back.
  - Repro: any `def f(message: str) -> str by model();`.
  - Worked around in `core/agent/agent.jac`, which fills `params` from the signature at import.
- **0.38.0 behaviour changes we hit on CI:**
  - **`@` refused in usernames.** A username with `@` is refused with `POLICY_VIOLATION` / `USERNAME_INVALID`, and the default `max_length` is 64. Customer sign-in names are now `<slug>:<local>:<domain>`, with `[serve.auth.username] max_length = 300`.
  - **Worker count sized from the CPU.** Pinned to `[serve.workers] count = 1`, and the real-server harness passes `-w 1`.
  - **New wording for a fractional `TOKEN_TTL_DAYS`.** It still refuses to start, but now says "must be a number, got '0.5'".
- **Unlogged from earlier work:**
  - checker E0076 on httpx2 and Playwright, which is why the SDK calls are in `::py::`;
  - the `jac run` + Playwright problem;
  - `toLowerCase`;
  - the `edge` keyword.
- **0.38.0 notes:**
  - Unmarked functions are now private. `sweep_holds`, `send_ticket_mail`, `resolve_payments` and `settle_callbacks` are not served, which is fine for scheduler tasks but worth confirming.
  - `jac start` is gone.
  - `jac run --serve` defaults to one worker per core.

## Next, when we come back

1. Watch #10277 and #10280 for maintainer replies; offer PRs if they agree with the fixes.
2. Update JI-015 and JI-042 with the 0.38.0 results and links. Mark JI-023 and JI-043 after re-testing them.
3. Write JI-050 and JI-051 as entries. Consider reporting JI-002 and JI-051 upstream.
4. Re-check tier 2 on 0.38.0.

## Logged since the pause

The owner asked on 2026-10-23 that Jac problems found during other work keep going into this log. Reporting upstream stays paused.

- **JI-052:** a stale prepared application served old client code, even with `--no-cache`. This is the most serious one, since tests can run code that's no longer in the source. Upstream needs a minimal repro first.
- **JI-053:** `jac fmt` moves `# jac:ignore` off the line it applies to.
- **JI-054:** a feature request. WebSockets can't send to chosen users, so private live updates (the support chat) poll instead. Reported as [jaseci-labs/jac#10319](https://github.com/jaseci-labs/jac/issues/10319) on 2026-10-23, once Phase 13 was done, as the owner asked (without the hotel analogy, which stays in our entry).
- JI-050 and JI-051 (above) are still candidates, not written up.
