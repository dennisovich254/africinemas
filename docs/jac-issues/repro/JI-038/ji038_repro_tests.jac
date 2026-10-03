"""JI-038: does a conflict at commit ever end in a 200 whose write was rolled back?

Boots counter_app.jac on a real server (jac run, embedded Postgres) and sends BUMPS
increments of one counter at once, as one signed-in user. Run from the repo root:

    jac test docs/jac-issues/repro/JI-038/ji038_repro_tests.jac -v

Documented behaviour: final count == bumps answered 200 (losers replayed, or 409).
The first test uses plain Jac (it passed, 2026-10-03: Jac handles plain conflicts). The
second (variant B) switches the request's root to the counter's owner mid-request, as
the app's act_as does; it passed too. Variants C and D have the hold path's shape:
every request loads all the nodes and writes a different one, flushing in full; D also
switches roots.
"""

import os;
import json;
import shutil;
import tempfile;
import from concurrent.futures { ThreadPoolExecutor }
import from pathlib { Path }
import from tests.support.real_server { RealServer, http_call, remove_project }

glob HERE: Path = Path(__file__).resolve().parent,
     REPO_ROOT: Path = Path(__file__).resolve().parents[4],
     BUMPS: int = 50,
     SPOTS: int = 60,
     APP_TOML: str = """[project]
name = "ji038-repro"
version = "0.1.0"
default-app = "api"

[apps.api]
kind = "service"
entry-point = "main"

[placement]
default = "server"
""";

def _project -> str {
    workdir = tempfile.mkdtemp(prefix="ji038-");
    shutil.copy(HERE / "counter_app.jac", Path(workdir) / "main.jac");
    (Path(workdir) / "jac.toml").write_text(APP_TOML);
    (Path(workdir) / ".jac").mkdir();
    os.symlink(REPO_ROOT / ".jac" / "venv", Path(workdir) / ".jac" / "venv");
    return workdir;
}

test "concurrent bumps: the count equals the bumps answered 200" {
    workdir = _project();
    server = RealServer(workdir=workdir, env=dict(os.environ));
    try {
        server.start();
        token = server.register("counter_user");
        server.call("setup", {}, token);
        bump = lambda (_: int) -> int { return http_call(
            "POST", f"{server.base()}/function/bump", {}, token
        )[0]; };
        with ThreadPoolExecutor(max_workers=BUMPS) as pool {
            statuses = list(pool.map(bump, range(BUMPS)));
        }
        final = server.call("hits", {}, token);
        log = server.log();
        verdict = {
            "bumps": BUMPS,
            "answered_200": statuses.count(200),
            "answered_409": statuses.count(409),
            "other": [
                s
                for s in statuses
                if s not in [200, 409]
            ],
            "final_count": final,
            "commit_on_close_failed_lines": log.count("commit on close failed")
        };
        print(f"\nJI-038 verdict: {json.dumps(verdict)}");
        assert final == statuses.count(200) , (
            f"lost writes behind 200 answers: {verdict}"
        );
    } finally {
        server.stop(drop=True);
        remove_project(workdir);
    }
}

test "variant B: bumps that switch to the owner's root, as the app does" {
    workdir = _project();
    server = RealServer(workdir=workdir, env=dict(os.environ));
    try {
        server.start();
        token = server.register("counter_owner");
        server.call("setup", {}, token);
        owner = server.call("owner_root", {}, token);
        bump = lambda (_: int) -> int { return http_call(
            "POST", f"{server.base()}/function/bump_as", {"owner": owner}
        )[0]; };
        with ThreadPoolExecutor(max_workers=BUMPS) as pool {
            statuses = list(pool.map(bump, range(BUMPS)));
        }
        final = server.call("hits", {}, token);
        log = server.log();
        verdict = {
            "bumps": BUMPS,
            "answered_200": statuses.count(200),
            "answered_409": statuses.count(409),
            "other": [
                s
                for s in statuses
                if s not in [200, 409]
            ],
            "final_count": final,
            "commit_on_close_failed_lines": log.count("commit on close failed")
        };
        print(f"\nJI-038 variant B verdict: {json.dumps(verdict)}");
        assert final == statuses.count(200) , (
            f"lost writes behind 200 answers: {verdict}"
        );
    } finally {
        server.stop(drop=True);
        remove_project(workdir);
    }
}

def _spots_race(name: str, as_owner: bool) {  # jac:ignore[W1037]
    # SPOTS requests at once, each taking a different spot after loading all of them.
    workdir = _project();
    server = RealServer(workdir=workdir, env=dict(os.environ));
    try {
        server.start();
        token = server.register(f"spot_owner_{name}");
        server.call("setup_spots", {"count": SPOTS}, token);
        owner = server.call("owner_root", {}, token);
        def take(n: int) -> int {
            if as_owner {
                return http_call(
                    "POST",
                    f"{server.base()}/function/take_as",
                    {"owner": owner, "n": n}
                )[0];
            }
            return http_call("POST", f"{server.base()}/function/take", {"n": n}, token)[
                0
            ];
        }
        with ThreadPoolExecutor(max_workers=SPOTS) as pool {
            statuses = list(pool.map(take, range(SPOTS)));
        }
        final = server.call("taken_count", {}, token);
        log = server.log();
        verdict = {
            "requests": SPOTS,
            "answered_200": statuses.count(200),
            "other": [
                s
                for s in statuses
                if s != 200
            ],
            "spots_taken": final,
            "commit_on_close_failed_lines": log.count("commit on close failed"),
            "permission_denied_lines": log.count("Permission denied")
        };
        print(f"\nJI-038 variant {name} verdict: {json.dumps(verdict)}");
        assert final == statuses.count(200) , (
            f"lost writes behind 200 answers: {verdict}"
        );
    } finally {
        server.stop(drop=True);
        remove_project(workdir);
    }
}

test "variant C: each request loads every spot and takes a different one" {
    _spots_race("C", False);
}

test "variant D: as C, switching to the owner's root, as the app does" {
    _spots_race("D", True);
}
