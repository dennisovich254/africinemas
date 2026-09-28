"""P2.1: concurrent claims of one slug converge on a single owner (real server).

Eight requests race to claim the same slug for eight different tenants. Exactly one
may win and every caller must be told the same owner. Jac's graph find-or-create
failed this test (JI-024); the atomic claim (ADR-0007) is what makes it pass.
"""

import os;
import shutil;
import tempfile;
import from concurrent.futures { ThreadPoolExecutor }
import from pathlib { Path }
import from tests.support.real_server { RealServer, remove_project }

glob REPO_ROOT: Path = Path(__file__).resolve().parent.parent.parent,
     RACERS: int = 8,
     APP_TOML: str = """[project]
name = "tenancy-race"
version = "0.1.0"
default-app = "api"

[apps.api]
kind = "service"
entry-point = "main"
""";

def _project -> str {
    workdir = tempfile.mkdtemp(prefix="africinemas-race-");
    shutil.copy(
        REPO_ROOT / "tests" / "apps" / "tenancy_app.jac", Path(workdir) / "main.jac"
    );
    shutil.copytree(REPO_ROOT / "core", Path(workdir) / "core");
    (Path(workdir) / "jac.toml").write_text(APP_TOML);
    (Path(workdir) / ".jac").mkdir();
    os.symlink(REPO_ROOT / ".jac" / "venv", Path(workdir) / ".jac" / "venv");
    return workdir;
}

test "concurrent claims of one slug converge on exactly one owner" {
    workdir = _project();
    server = RealServer(workdir=workdir, env=dict(os.environ));
    try {
        server.start();
        claim = lambda (i: int) -> str { return server.call(
            "t_claim", {"slug": "nova", "tenant_id": f"tenant-{i}"}
        )["owner"]; };
        with ThreadPoolExecutor(max_workers=RACERS) as pool {
            owners = list(pool.map(claim, range(RACERS)));
        }
        assert len(set(owners)) == 1 , f"callers were told different owners: {owners}";
        winner = owners[0];
        assert winner in [f"tenant-{i}" for i in range(RACERS)];
        assert server.call("t_lookup", {"slug": "nova"}) == winner;
    } finally {
        server.stop(drop=True);
        remove_project(workdir);
    }
}
