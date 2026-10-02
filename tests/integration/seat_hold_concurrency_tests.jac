"""P4.3: many visitors holding the same seats at once (real server, real concurrency).

Each seat is an atomic claim (ADR-0007), a single statement on a primary key, so of any
number of simultaneous holds on one seat exactly one wins. A request for several seats
holds all of them or none: when one is taken, the claims it already made are released.
"""

import os;
import shutil;
import tempfile;
import from concurrent.futures { ThreadPoolExecutor }
import from datetime { datetime, timedelta, timezone }
import from pathlib { Path }
import from tests.support.real_server { RealServer, remove_project }

glob REPO_ROOT: Path = Path(__file__).resolve().parent.parent.parent,
     RACERS: int = 50,
     APP_TOML: str = """[project]
name = "seat-hold-race"
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
import from core.catalog.screening_api { create_screening, schedule_screening, publish_screening }  # jac:ignore[W2037]
import from core.catalog.storefront_api { public_seat_availability }  # jac:ignore[W2037]
import from core.booking.hold_api { hold_seats }  # jac:ignore[W2037]
""";

def _project -> str {
    workdir = tempfile.mkdtemp(prefix="africinemas-holds-");
    (Path(workdir) / "main.jac").write_text(APP_MAIN);
    shutil.copytree(REPO_ROOT / "core", Path(workdir) / "core");
    (Path(workdir) / "jac.toml").write_text(APP_TOML);
    (Path(workdir) / ".jac").mkdir();
    os.symlink(REPO_ROOT / ".jac" / "venv", Path(workdir) / ".jac" / "venv");
    return workdir;
}

def _showtime(server: RealServer) -> str {
    # A cinema with a published three-seat showtime; returns the showtime's id.
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
            "cols": 3,
            "seats": [{"label": f"A{i + 1}", "row": 0, "col": i} for i in range(3)]
        },
        owner
    );
    server.call("publish_layout", {"tenant": "nova", "auditorium_id": screen}, owner);
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
    for step in ["schedule_screening", "publish_screening"] {
        assert server.call(step, {"tenant": "nova", "screening_id": screening}, owner)[
            "ok"
        ];
    }
    return screening;
}

test "fifty visitors holding one seat at once: exactly one gets it" {
    workdir = _project();
    server = RealServer(workdir=workdir, env=dict(os.environ));
    try {
        server.start();
        screening = _showtime(server);
        hold = lambda (i: int) -> any { return server.call(
            "hold_seats",
            {
                "slug": "nova",
                "screening_id": screening,
                "holder": f"racer-{i:04d}-0123456789abcdef",
                "labels": ["A1"]
            }
        ); };
        with ThreadPoolExecutor(max_workers=RACERS) as pool {
            results = list(pool.map(hold, range(RACERS)));
        }
        won = [
            r
            for r in results
            if r["ok"]
        ];
        assert len(won) == 1 , [
            r.get("error")
            for r in results
            if not r["ok"]
        ][:5];
        assert all(
            r["error"]["code"] == "seats_taken"
            for r in results
            if not r["ok"]
        ) , results;
        seats = server.call(
            "public_seat_availability", {"slug": "nova", "screening_id": screening}
        )["seats"];
        assert [s["state"] for s in seats]
            == ["held", "available", "available"] , seats;
    } finally {
        server.stop(drop=True);
        remove_project(workdir);
    }
}

test "overlapping holds at once never leave anyone holding part of a request" {
    workdir = _project();
    server = RealServer(workdir=workdir, env=dict(os.environ));
    try {
        server.start();
        screening = _showtime(server);
        wanted = [["A1", "A2"], ["A2", "A3"]];
        hold = lambda (i: int) -> any { return server.call(
            "hold_seats",
            {
                "slug": "nova",
                "screening_id": screening,
                "holder": f"overlap-{i:04d}-0123456789abcdef",
                "labels": wanted[i % 2]
            }
        ); };
        with ThreadPoolExecutor(max_workers=20) as pool {
            results = list(pool.map(hold, range(20)));
        }
        won = [
            r
            for r in results
            if r["ok"]
        ];
        # A2 is in every request, so exactly one request wins, with all its seats.
        assert len(won) == 1 , [
            r.get("error")
            for r in results
            if not r["ok"]
        ][:5];
        held = won[0]["hold"]["seats"];
        seats = server.call(
            "public_seat_availability", {"slug": "nova", "screening_id": screening}
        )["seats"];
        states = {s["label"]: s["state"] for s in seats};
        assert [
            label
            for label in ["A1", "A2", "A3"]
            if states[label] == "held"
        ]
            == held , (states, held);
    } finally {
        server.stop(drop=True);
        remove_project(workdir);
    }
}
