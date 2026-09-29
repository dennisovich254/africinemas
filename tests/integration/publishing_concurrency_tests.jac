"""P3.5b: several requests publishing one screening at once (real server).

Publishing creates the screening's seat inventory and its storefront entry. Concurrent
publishes all change the screening's state, so the database lets one through and re-runs
the others, which then find it already published: exactly one set of SeatSlots and one
storefront entry are made.
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
name = "publish-race"
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
import from core.catalog.screening_api {
    create_screening,  # jac:ignore[W2037]
    schedule_screening,  # jac:ignore[W2037]
    publish_screening,  # jac:ignore[W2037]
    list_seat_slots,  # jac:ignore[W2037]
    public_screenings
}
""";

def _project -> str {
    workdir = tempfile.mkdtemp(prefix="africinemas-publish-");
    (Path(workdir) / "main.jac").write_text(APP_MAIN);
    shutil.copytree(REPO_ROOT / "core", Path(workdir) / "core");
    (Path(workdir) / "jac.toml").write_text(APP_TOML);
    (Path(workdir) / ".jac").mkdir();
    os.symlink(REPO_ROOT / ".jac" / "venv", Path(workdir) / ".jac" / "venv");
    return workdir;
}

test "concurrent publishes of one screening: one inventory and one storefront entry" {
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
        seats = [{"label": f"A{c + 1}", "row": 0, "col": c} for c in range(6)];
        server.call(
            "save_layout",
            {
                "tenant": "nova",
                "auditorium_id": screen,
                "rows": 1,
                "cols": 6,
                "seats": seats
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
        screening = server.call(
            "create_screening",
            {
                "tenant": "nova",
                "auditorium_id": screen,
                "movie_id": movie,
                "starts_at": start.isoformat()
            },
            owner
        )["screening"]["screening_id"];
        server.call(
            "schedule_screening", {"tenant": "nova", "screening_id": screening}, owner
        );
        publish = lambda (_: int) -> any { return server.call(
            "publish_screening", {"tenant": "nova", "screening_id": screening}, owner
        ); };
        with ThreadPoolExecutor(max_workers=RACERS) as pool {
            results = list(pool.map(publish, range(RACERS)));
        }
        assert len(
            [
                r
                for r in results
                if r["ok"]
            ]
        )
            == 1 , results;
        assert all(
            r["error"]["code"] == "invalid_transition"
            for r in results
            if not r["ok"]
        ) , results;
        slots = server.call(
            "list_seat_slots", {"tenant": "nova", "screening_id": screening}, owner
        )["slots"];
        assert sorted([x["label"] for x in slots])
            == sorted([x["label"] for x in seats]) , slots;
        shown = server.call("public_screenings", {"slug": "nova"})["screenings"];
        assert [x["screening_id"] for x in shown] == [screening] , shown;
    } finally {
        server.stop(drop=True);
        remove_project(workdir);
    }
}
