"""P4.7, spike S5: seat holds under opening-night load (architecture §25, §138).

Boots a real server (tests/apps/order_app.jac as main.jac) and sends 200 hold requests
at once, as anonymous visitors, in two shapes:

- hot seat: everyone wants the same seat. Exactly one wins; everyone else is told
  "seats_taken"; nothing fails.
- opening night: a 10 x 20 hall; each visitor wants two seats side by side, picked at
  random (seeded, so every run asks the same). No seat is held by two visitors, every
  winner holds all their seats, and every request is answered.

Correctness is absolute. Speed is measured (p50, p95, p99, slowest) with the refusal
rate, written to load/artifacts/s5-<scenario>.json and printed; it must stay within the
targets recorded in docs/adr/0014-seat-hold-load-targets.md (TARGETS below mirrors
it). Not part of the test suite: run with scripts/load.sh.
"""

import os;
import json;
import time;
import random;
import shutil;
import tempfile;
import from concurrent.futures { ThreadPoolExecutor }
import from pathlib { Path }
import from tests.support.real_server {
    RealServer,
    http_call,
    remove_project,
    published_showtime
}

glob REPO_ROOT: Path = Path(__file__).resolve().parent.parent,
     VISITORS: int = int(os.environ.get("LOAD_VISITORS", "200")),
     ROWS: int = 10,
     COLS: int = 20,
     SEED: int = 4_7,
     # ADR-0014. Seconds, measured at the client, for one hold request.
     TARGETS: dict[str, float] = {"p95_s": 5.0, "p99_s": 8.0, "max_s": 15.0},
     APP_TOML: str = """[project]
name = "hold-load"
version = "0.1.0"
default-app = "api"

[apps.api]
kind = "service"
entry-point = "main"

[serve]
conflict_backoff_ms = 20

[placement]
default = "server"
""";

def _project -> str {
    workdir = tempfile.mkdtemp(prefix="africinemas-load-");
    shutil.copy(
        REPO_ROOT / "tests" / "apps" / "order_app.jac", Path(workdir) / "main.jac"
    );
    shutil.copytree(REPO_ROOT / "core", Path(workdir) / "core");
    (Path(workdir) / "jac.toml").write_text(APP_TOML);
    (Path(workdir) / ".jac").mkdir();
    os.symlink(REPO_ROOT / ".jac" / "venv", Path(workdir) / ".jac" / "venv");
    return workdir;
}

def _holder(i: int) -> str {
    return f"load-visitor-{i:05d}-0123456789";
}

def _hold(
    server: RealServer, screening: str, holder: str, labels: list[str]
) -> dict[str, any] {  # jac:ignore[W1037]
    # One visitor's hold, timed; a transport failure or non-200 is recorded, not raised.
    started = time.perf_counter();
    try {
        (status, body) = http_call(
            "POST",
            f"{server.base()}/function/hold_seats",
            {
                "slug": "nova",
                "screening_id": screening,
                "holder": holder,
                "labels": labels
            }
        );
    } except Exception as e {
        return {
            "holder": holder,
            "labels": labels,
            "seconds": time.perf_counter() - started,
            "status": 0,
            "error": str(e)
        };
    }
    result = body["data"]["result"] if status == 200 else None;
    return {
        "holder": holder,
        "labels": labels,
        "seconds": time.perf_counter() - started,
        "status": status,
        "ok": bool(result and result["ok"]),
        "code": "" if not result or result["ok"] else result["error"]["code"],
        "held": result["hold"]["seats"] if result and result["ok"] else []
    };
}

def _race(
    server: RealServer, screening: str, wants: list[list[str]]
) -> list[dict[str, any]] {  # jac:ignore[W1037]
    # Everyone at once: one thread per visitor, all started together.
    jobs = [(_holder(i), wants[i]) for i in range(len(wants))];
    with ThreadPoolExecutor(max_workers=len(jobs)) as pool {
        return list(
            pool.map(
                lambda (job: tuple[str, list[str]]) -> any { return _hold(
                    server, screening, job[0], job[1]
                ); },
                jobs
            )  # jac:ignore[W1037]
        );
    }
}

def _percentile(values: list[float], share: float) -> float {
    ordered = sorted(values);
    return ordered[min(len(ordered) - 1, int(share * len(ordered)))];
}

def _report(name: str, results: list[dict[str, any]]) -> dict[str, any] {  # jac:ignore[W1037]
    times = [r["seconds"] for r in results];
    summary = {
        "scenario": name,
        "visitors": len(results),
        "won": len(
            [
                r
                for r in results
                if r.get("ok")
            ]
        ),
        "refused": len(
            [
                r
                for r in results
                if r.get("status") == 200 and not r.get("ok")
            ]
        ),
        "failed": len(
            [
                r
                for r in results
                if r.get("status") != 200
            ]
        ),
        "refusal_rate": round(
            len(
                [
                    r
                    for r in results
                    if r.get("status") == 200 and not r.get("ok")
                ]
            )
                / len(results),
            3
        ),
        "p50_s": round(_percentile(times, 0.50), 3),
        "p95_s": round(_percentile(times, 0.95), 3),
        "p99_s": round(_percentile(times, 0.99), 3),
        "max_s": round(max(times), 3),
        "codes": sorted(
            set(
                r.get("code", "")
                for r in results
                if r.get("code")
            )
        )
    };
    out = REPO_ROOT / "load" / "artifacts";
    out.mkdir(exist_ok=True);
    (out / f"s5-{name}.json").write_text(json.dumps(summary, indent=2));
    print(f"\nS5 {name}: {json.dumps(summary)}");
    return summary;
}

def _within_targets(summary: dict[str, any]) {  # jac:ignore[W1037]
    for (key, limit) in TARGETS.items() {
        assert summary[key] <= limit , f"{summary['scenario']}: {key} {summary[key]} > {limit}";
    }
}

def _states(server: RealServer, screening: str) -> dict[str, str] {
    seats = server.call(
        "public_seat_availability", {"slug": "nova", "screening_id": screening}
    )["seats"];
    return {s["label"]: s["state"] for s in seats};
}

test "hot seat: two hundred visitors want one seat; one gets it, nothing fails" {
    workdir = _project();
    server = RealServer(workdir=workdir, env=dict(os.environ));
    try {
        server.start();
        screening = published_showtime(server, ROWS, COLS);
        results = _race(server, screening, [["E10"] for _ in range(VISITORS)]);
        summary = _report("hot-seat", results);
        assert summary["failed"] == 0 , [
            r
            for r in results
            if r.get("status") != 200
        ][:3];
        assert summary["won"] == 1 , summary;
        assert summary["codes"] == ["seats_taken"] , summary;
        assert _states(server, screening)["E10"] == "held";
        _within_targets(summary);
    } finally {
        server.stop(drop=True);
        remove_project(workdir);
    }
}

test "opening night: two hundred visitors, two seats each; no seat held twice" {
    workdir = _project();
    server = RealServer(workdir=workdir, env=dict(os.environ));
    try {
        server.start();
        screening = published_showtime(server, ROWS, COLS);
        pick = random.Random(SEED);
        wants: list[list[str]] = [];
        for _ in range(VISITORS) {
            row = chr(65 + pick.randrange(ROWS));
            col = pick.randrange(COLS - 1) + 1;
            wants.append([f"{row}{col}", f"{row}{col + 1}"]);
        }
        results = _race(server, screening, wants);
        summary = _report("opening-night", results);
        assert summary["failed"] == 0 , [
            r
            for r in results
            if r.get("status") != 200
        ][:3];
        assert set(summary["codes"]) <= {"seats_taken"} , summary;
        # Winners hold all they asked for, and no seat is in two winners' holds.
        owners: dict[str, str] = {};
        for r in results {
            if r.get("ok") {
                assert sorted(r["held"]) == sorted(r["labels"]) , r;
                for label in r["held"] {
                    assert label not in owners , (
                        label,
                        owners.get(label),
                        r["holder"]
                    );
                    owners[label] = r["holder"];
                }
            }
        }
        # And the seat map agrees: exactly the winners' seats are held.
        held = sorted(
            [
                l
                for (l, s) in _states(server, screening).items()
                if s == "held"
            ]
        );
        assert held == sorted(owners.keys()) , (len(held), len(owners));
        assert summary["won"] > 0;
        _within_targets(summary);
    } finally {
        server.stop(drop=True);
        remove_project(workdir);
    }
}
