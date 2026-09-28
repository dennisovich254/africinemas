"""P2.5: one invite, several people accepting at the same moment (real server).

Exactly one accept may succeed; the others are told the invite is no longer valid, and
the staff list gains exactly one member.
"""

import os;
import shutil;
import tempfile;
import from concurrent.futures { ThreadPoolExecutor }
import from pathlib { Path }
import from tests.support.real_server { RealServer, remove_project }

glob REPO_ROOT: Path = Path(__file__).resolve().parent.parent.parent,
     RACERS: int = 5,
     APP_TOML: str = """[project]
name = "invite-race"
version = "0.1.0"
default-app = "api"

[apps.api]
kind = "service"
entry-point = "main"

[placement]
default = "server"
""",
     # The production endpoints without the web client (main.jac also builds the UI).
     APP_MAIN: str = """import from core.tenancy.signup { create_cinema, my_cinemas }  # jac:ignore[W2037]
import from core.tenancy.tenant_api { my_access, rename_cinema, start_shift, end_shift }  # jac:ignore[W2037]
import from core.tenancy.staff_api {
    invite_staff,
    accept_invite,
    list_staff,
    change_staff_roles,
    set_staff_status,
    remove_staff
}  # jac:ignore[W2037]
""";

def _project -> str {
    workdir = tempfile.mkdtemp(prefix="africinemas-invite-");
    (Path(workdir) / "main.jac").write_text(APP_MAIN);
    shutil.copytree(REPO_ROOT / "core", Path(workdir) / "core");
    (Path(workdir) / "jac.toml").write_text(APP_TOML);
    (Path(workdir) / ".jac").mkdir();
    os.symlink(REPO_ROOT / ".jac" / "venv", Path(workdir) / ".jac" / "venv");
    return workdir;
}

test "concurrent accepts of one invite: exactly one joins" {
    workdir = _project();
    server = RealServer(workdir=workdir, env=dict(os.environ));
    try {
        server.start();
        owner = server.register("owner");
        server.call("create_cinema", {"name": "Nova Cinemas", "slug": "nova"}, owner);
        server.call("start_shift", {"tenant": "nova"}, owner);
        token = server.call(
            "invite_staff", {"tenant": "nova", "role": "usher", "venue_id": ""}, owner
        )["token"];
        racers = [server.register(f"racer_{i}") for i in range(RACERS)];
        accept = lambda (t: str) -> any { return server.call(
            "accept_invite", {"token": token}, t
        ); };
        with ThreadPoolExecutor(max_workers=RACERS) as pool {
            results = list(pool.map(accept, racers));
        }
        winners = [
            r
            for r in results
            if r["ok"]
        ];
        assert len(winners) == 1 , results;
        assert all(
            r["error"]["code"] == "invalid_invite"
            for r in results
            if not r["ok"]
        ) , results;
        staff = server.call("list_staff", {"tenant": "nova"}, owner)["staff"];
        assert sorted([s["roles"] for s in staff]) == [["owner"], ["usher"]] , staff;
    } finally {
        server.stop(drop=True);
        remove_project(workdir);
    }
}
