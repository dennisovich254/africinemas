"""P3.2: several saves of one screen's layout at the same moment (real server).

A new layout version is created when a screen has no draft (its first layout, or after
a publish). Saves of one screen take its edit lock (an atomic claim, ADR-0007), so
concurrent saves never collide in the database: each either saves (creating the version
or updating the draft) or is refused with layout_busy. Exactly one version is created,
and no request fails with a server error.
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
name = "layout-race"
version = "0.1.0"
default-app = "api"

[apps.api]
kind = "service"
entry-point = "main"

[serve]
conflict_backoff_ms = 20

[placement]
default = "server"
""",
     # The production endpoints without the web client (main.jac also builds the UI).
     APP_MAIN: str = """import from core.tenancy.signup { create_cinema }  # jac:ignore[W2037]
import from core.tenancy.tenant_api { start_shift, my_access }  # jac:ignore[W2037]
import from core.catalog.venue_api { create_venue, create_auditorium, list_venues }  # jac:ignore[W2037]
import from core.catalog.layout_api { save_layout, publish_layout, list_layouts }  # jac:ignore[W2037]
""";

def _project -> str {
    workdir = tempfile.mkdtemp(prefix="africinemas-layout-");
    (Path(workdir) / "main.jac").write_text(APP_MAIN);
    shutil.copytree(REPO_ROOT / "core", Path(workdir) / "core");
    (Path(workdir) / "jac.toml").write_text(APP_TOML);
    (Path(workdir) / ".jac").mkdir();
    os.symlink(REPO_ROOT / ".jac" / "venv", Path(workdir) / ".jac" / "venv");
    return workdir;
}

def _race(server: RealServer, owner: str, screen: str) -> list[dict[str, any]] {  # jac:ignore[W1037]
    save = lambda (i: int) -> any { return server.call(
        "save_layout",
        {
            "tenant": "nova",
            "auditorium_id": screen,
            "rows": 1,
            "cols": RACERS,
            "seats": [{"label": f"A{i + 1}", "row": 0, "col": i}]
        },
        owner
    ); };
    with ThreadPoolExecutor(max_workers=RACERS) as pool {
        results = list(pool.map(save, range(RACERS)));
    }
    assert any(r["ok"] for r in results) , results;
    assert all(
        r["ok"] or r["error"]["code"] == "layout_busy" for r in results
    ) , results;
    return results;
}

test "concurrent saves create exactly one new version" {
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
        screen = server.call(
            "create_auditorium",
            {"tenant": "nova", "venue_id": venue, "name": "Screen 1"},
            owner
        )["auditorium"]["auditorium_id"];
        listing = lambda -> any { return server.call(
            "list_layouts", {"tenant": "nova", "auditorium_id": screen}, owner
        ); };
        # The first layout: one draft v1, however many saves arrive.
        _race(server, owner, screen);
        first = listing();
        assert [l["version"] for l in first["layouts"]] == [1] , first;
        assert server.call(
            "publish_layout", {"tenant": "nova", "auditorium_id": screen}, owner
        )["ok"];
        # Editing the published v1: one draft v2.
        _race(server, owner, screen);
        second = listing();
        assert [(l["version"], l["status"]) for l in second["layouts"]]
            == [(1, "published"), (2, "draft")] , second;
    } finally {
        server.stop(drop=True);
        remove_project(workdir);
    }
}
