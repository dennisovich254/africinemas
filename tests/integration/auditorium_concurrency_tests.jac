"""P3.1: several requests creating the same screen name at one venue at once (real server).

Screen names are unique per venue through an atomic claim (ADR-0007): a graph
check-then-create would let concurrent requests all pass the check (JI-024). Exactly one
create may succeed; the others are told the name is taken, and the venue lists one
screen.
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
name = "auditorium-race"
version = "0.1.0"
default-app = "api"

[apps.api]
kind = "service"
entry-point = "main"

[placement]
default = "server"
""",
     # The production endpoints without the web client (main.jac also builds the UI).
     APP_MAIN: str = """import from core.tenancy.signup { create_cinema }  # jac:ignore[W2037]
import from core.tenancy.tenant_api { start_shift }  # jac:ignore[W2037]
import from core.catalog.venue_api { create_venue, list_venues, create_auditorium }  # jac:ignore[W2037]
""";

def _project -> str {
    workdir = tempfile.mkdtemp(prefix="africinemas-auditorium-");
    (Path(workdir) / "main.jac").write_text(APP_MAIN);
    shutil.copytree(REPO_ROOT / "core", Path(workdir) / "core");
    (Path(workdir) / "jac.toml").write_text(APP_TOML);
    (Path(workdir) / ".jac").mkdir();
    os.symlink(REPO_ROOT / ".jac" / "venv", Path(workdir) / ".jac" / "venv");
    return workdir;
}

test "concurrent creates of one screen name: exactly one is made" {
    workdir = _project();
    server = RealServer(workdir=workdir, env=dict(os.environ));
    try {
        server.start();
        owner = server.register("owner");
        server.call("create_cinema", {"name": "Nova Cinemas", "slug": "nova"}, owner);
        server.call("start_shift", {"tenant": "nova"}, owner);
        venue = server.call(
            "create_venue",
            {"tenant": "nova", "name": "Westgate", "city": "", "address": ""},
            owner
        )["venue"]["venue_id"];
        create = lambda (_: int) -> any { return server.call(
            "create_auditorium",
            {"tenant": "nova", "venue_id": venue, "name": "Screen 1"},
            owner
        ); };
        with ThreadPoolExecutor(max_workers=RACERS) as pool {
            results = list(pool.map(create, range(RACERS)));
        }
        made = [
            r
            for r in results
            if r["ok"]
        ];
        assert len(made) == 1 , results;
        assert all(
            r["error"]["code"] == "name_taken"
            for r in results
            if not r["ok"]
        ) , results;
        venues = server.call("list_venues", {"tenant": "nova"}, owner)["venues"];
        assert [a["name"] for a in venues[0]["auditoriums"]] == ["Screen 1"] , venues;
    } finally {
        server.stop(drop=True);
        remove_project(workdir);
    }
}
