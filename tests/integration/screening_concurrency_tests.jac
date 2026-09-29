"""P3.5a: several requests scheduling the same time on one screen at once (real server).

Two screenings created concurrently could each pass the overlap check before either is
saved. Scheduling on a screen takes its schedule lock (an atomic claim, ADR-0007), so
exactly one is created; the others are told the time overlaps or the screen is busy.
"""

import os;
import shutil;
import tempfile;
import from concurrent.futures { ThreadPoolExecutor }
import from datetime { datetime, timedelta, timezone }
import from pathlib { Path }
import from tests.support.real_server { RealServer, remove_project }

glob REPO_ROOT: Path = Path(__file__).resolve().parent.parent.parent,
     RACERS: int = 5,
     APP_TOML: str = """[project]
name = "screening-race"
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
import from core.tenancy.tenant_api { start_shift }  # jac:ignore[W2037]
import from core.catalog.venue_api { create_venue, create_auditorium }  # jac:ignore[W2037]
import from core.catalog.layout_api { save_layout, publish_layout }  # jac:ignore[W2037]
import from core.catalog.movie_api { create_movie }  # jac:ignore[W2037]
import from core.catalog.screening_api { create_screening, list_screenings }  # jac:ignore[W2037]
""";

def _project -> str {
    workdir = tempfile.mkdtemp(prefix="africinemas-screening-");
    (Path(workdir) / "main.jac").write_text(APP_MAIN);
    shutil.copytree(REPO_ROOT / "core", Path(workdir) / "core");
    (Path(workdir) / "jac.toml").write_text(APP_TOML);
    (Path(workdir) / ".jac").mkdir();
    os.symlink(REPO_ROOT / ".jac" / "venv", Path(workdir) / ".jac" / "venv");
    return workdir;
}

test "concurrent creates of one time on one screen: exactly one is scheduled" {
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
        server.call(
            "save_layout",
            {
                "tenant": "nova",
                "auditorium_id": screen,
                "rows": 1,
                "cols": 1,
                "seats": [{"label": "A1", "row": 0, "col": 0}]
            },
            owner
        );
        server.call(
            "publish_layout", {"tenant": "nova", "auditorium_id": screen}, owner
        );
        movie = server.call(
            "create_movie",
            {
                "tenant": "nova",
                "title": "Rafiki",
                "synopsis": "",
                "runtime_minutes": 90,
                "age_rating": "18",
                "genres": [],
                "language": ""
            },
            owner
        )["movie"]["movie_id"];
        start = (datetime.now(timezone.utc) + timedelta(days=2)).replace(microsecond=0);
        # Five different times, all within one another's running time.
        create = lambda (i: int) -> any { return server.call(
            "create_screening",
            {
                "tenant": "nova",
                "auditorium_id": screen,
                "movie_id": movie,
                "starts_at": (start + timedelta(minutes=10 * i)).isoformat()
            },
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
            r["error"]["code"] in ("overlap", "screen_busy")
            for r in results
            if not r["ok"]
        ) , results;
        listed = server.call(
            "list_screenings", {"tenant": "nova", "auditorium_id": screen}, owner
        )["screenings"];
        assert len(listed) == 1 , listed;
    } finally {
        server.stop(drop=True);
        remove_project(workdir);
    }
}
