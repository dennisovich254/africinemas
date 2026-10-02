"""P4.4: the hold expiry sweeper runs on its own, on a schedule (real server).

The scheduler only runs in a served process, so this boots a real server from a temp
project (tests/apps/sweeper_app.jac as main.jac, the scheduler on, the sweep every
second) and waits for a lapsed hold to be swept. What one sweep does, and that running
it again changes nothing, is in hold_sweeper_tests.jac.
"""

import os;
import shutil;
import tempfile;
import from pathlib { Path }
import from tests.support.real_server {
    RealServer,
    wait_until,
    remove_project,
    published_showtime
}

glob REPO_ROOT: Path = Path(__file__).resolve().parent.parent.parent,
     ANNA: str = "holder-anna-0123456789abcdef",
     APP_TOML: str = """[project]
name = "hold-sweeper"
version = "0.1.0"
default-app = "api"

[apps.api]
kind = "service"
entry-point = "main"

[placement]
default = "server"

[scale.scheduler]
enabled = true
""";

def _project -> str {
    workdir = tempfile.mkdtemp(prefix="africinemas-sweeper-");
    shutil.copy(
        REPO_ROOT / "tests" / "apps" / "sweeper_app.jac", Path(workdir) / "main.jac"
    );
    shutil.copytree(REPO_ROOT / "core", Path(workdir) / "core");
    (Path(workdir) / "jac.toml").write_text(APP_TOML);
    (Path(workdir) / ".jac").mkdir();
    os.symlink(REPO_ROOT / ".jac" / "venv", Path(workdir) / ".jac" / "venv");
    return workdir;
}

test "a lapsed hold is swept without anyone asking" {
    workdir = _project();
    env = dict(os.environ);
    env["AFRICINEMAS_HOLD_SECONDS"] = "1";
    env["AFRICINEMAS_SWEEP_SECONDS"] = "1";
    server = RealServer(workdir=workdir, env=env);
    try {
        server.start();
        screening = published_showtime(server);
        held = server.call(
            "hold_seats",
            {
                "slug": "nova",
                "screening_id": screening,
                "holder": ANNA,
                "labels": ["A1"]
            }
        );
        assert held["ok"] , held;
        stored = lambda -> any { return server.call(
            "sw_stored", {"slug": "nova", "screening_id": screening}
        ); };
        swept = lambda -> bool { return stored()["holds"] == [[ANNA, "expired"]]; };
        assert wait_until(swept, 30) , f"not swept: {stored()}\n{server.log()[-2000:]}";
        assert stored()["slots"]["A1"] == "available";
        assert server.call("sw_seat_claim", {"screening_id": screening, "label": "A1"})
            is None;
        assert server.call("sw_open_holds") == 0;
    } finally {
        server.stop(drop=True);
        remove_project(workdir);
    }
}
