# ADR-0014: Seat holds under opening-night load (spike S5)

- **Status:** Accepted
- **Date:** 2026-10-03
- **Sub-phase:** P4.7
- **Code:** `core/booking/hold_api.jac`, `core/booking/order_api.jac`, `core/tenancy/principal.jac` (`commit_now`)
- **Tests:** `load/hold_load_tests.jac` (run with `scripts/load.sh`; not in the test suite)

## Context
Spike S5 (architecture §138) asks how holds behave when hundreds of visitors try at once (§25). The load test sends 200 anonymous holds at once to a real server, in two shapes: everyone wants one seat (hot seat), and everyone wants two adjacent seats on a 10 × 20 hall (opening night). The first runs found three problems:

1. Every hold read the whole seat map before trying for its seats: 35–45 s per hold.
2. Every new hold linked to the showtime node, so winners collided there; one ran out of retries (500).
3. Winners' writes were lost at session close while the visitor was told the hold succeeded (JI-038).

## Decision
1. **Correctness is absolute.** One winner per seat (atomic claims, ADR-0007), no seat held by two visitors, the seat map agrees with the winners, and no request fails. The load test asserts all of it every run.
2. **Claim first.** A hold claims its seats before reading anything else; those who lose answer at once. Only winners read the seat map, and they release what they claimed if a check then fails (never a seat already theirs).
3. **No shared node in the hold path.** A visitor's hold is found through a `VISITOR_HOLDS` claim, and a new hold hangs on its first seat, not on the showtime.
4. **Commit before answering** (JI-038). Hold and order writes end with `commit_now()`, so a conflict is replayed inside the request instead of being lost after the answer.
5. **Latency targets are regression guards from the measured baseline**, on the development machine (2-core Celeron N4020, one server worker, embedded Postgres), the slowest place this runs:

   | Scenario | Measured p50 / p95 / max | Target p95 / p99 / max |
   | --- | --- | --- |
   | Hot seat | 8.4 / 8.9 / 9.0 s | 12 / 14 / 18 s |
   | Opening night | 24.2 / 25.5 / 25.7 s | 32 / 35 / 40 s |

   The refusal rates (99.5% and 64%) follow from the scenarios and are reported, not targeted.

## Consequences
- 200 holds in the same second is an extreme opening night for one cinema; at this rate (about 8 to 25 holds a second on one slow worker) the queue clears within half a minute, and nothing is double-sold.
- Production runs several workers (`jac start --workers N`) on more cores, which multiplies throughput; the targets here are a floor, not the expectation.
- Next step for speed (plan 11.1c): holds that never touch the graph. The claims already decide who holds a seat; the seat map can read holds from the claims (one query per showtime), so a hold writes no node at all. Then re-measure, including with several workers.
- `commit_now()` is the rule for any write path that runs concurrently (Phase 5's payments included) until JI-038 is fixed in Jac.
