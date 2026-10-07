"""P6.2: one ticket scanned at many doors at once is redeemed once (real server, real
concurrency; architecture §47).

Redeeming claims the ticket atomically (ADR-0007) before marking it used, so of
racing scans exactly one succeeds and every other is told the ticket was already
redeemed. The ticket is stored as used once.
"""

import os;
import shutil;
import tempfile;
import from concurrent.futures { ThreadPoolExecutor }
import from pathlib { Path }
import from tests.support.real_server { RealServer, remove_project, published_showtime }

glob REPO_ROOT: Path = Path(__file__).resolve().parent.parent.parent,
     SCANNERS: int = 10,
     APP_TOML: str = """[project]
name = "redeem-race"
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
    workdir = tempfile.mkdtemp(prefix="africinemas-redeem-");
    shutil.copy(
        REPO_ROOT / "tests" / "apps" / "redeem_app.jac", Path(workdir) / "main.jac"
    );
    shutil.copytree(REPO_ROOT / "core", Path(workdir) / "core");
    (Path(workdir) / "jac.toml").write_text(APP_TOML);
    (Path(workdir) / ".jac").mkdir();
    os.symlink(REPO_ROOT / ".jac" / "venv", Path(workdir) / ".jac" / "venv");
    return workdir;
}

def _code(result: dict[str, any]) -> str {  # jac:ignore[W1037]
    return "" if result["ok"] else result["error"]["code"];
}

test "ten scans of one ticket at once redeem it exactly once" {
    workdir = _project();
    env = dict(os.environ);
    env["AFRICINEMAS_CLOCK_CONTROL"] = "1";
    env["AFRICINEMAS_TICKET_KEY"] = "race" * 10;
    server = RealServer(workdir=workdir, env=env);
    try {
        server.start();
        screening = published_showtime(server);
        owner = server.login("owner");
        where = {"slug": "nova", "screening_id": screening};
        ticket = server.call("race_ticket", where);
        server.call("race_freeze", {** where, "minutes": -30});
        scan = lambda (_: int) -> any { return server.call(
            "redeem_ticket",
            {"tenant": "nova", "screening_id": screening, "code": ticket["qr"]},
            owner
        ); };
        with ThreadPoolExecutor(max_workers=SCANNERS) as pool {
            results = list(pool.map(scan, range(SCANNERS)));
        }
        codes = sorted([_code(r) for r in results]);
        assert codes == [""] + ["already_redeemed"] * (SCANNERS - 1) , (
            codes,
            server.log()[-2000:]
        );
        stored = server.call("race_ticket_state", where);
        assert len(stored) == 1 and stored[0][1] == "used" and stored[0][2] , stored;
    } finally {
        server.stop(drop=True);
        remove_project(workdir);
    }
}
