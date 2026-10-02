"""P4.5: one order however many times it is sent at once (real server, real concurrency).

The idempotency key (architecture §26) is an atomic claim (ADR-0007) naming the order
made for it, so racing requests with one key make one order; the others get that
order, or are told it is still being made and to ask again. A hold is claimed by its
order too, so requests with different keys for the same seats still make one order.
"""

import os;
import shutil;
import tempfile;
import from concurrent.futures { ThreadPoolExecutor }
import from pathlib { Path }
import from tests.support.real_server { RealServer, remove_project, published_showtime }

glob REPO_ROOT: Path = Path(__file__).resolve().parent.parent.parent,
     RACERS: int = 20,
     ANNA: str = "holder-anna-0123456789abcdef",
     APP_TOML: str = """[project]
name = "order-race"
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
     # The production endpoints without the web client, and a probe counting orders.
     APP_MAIN: str = """import from core.tenancy.signup { create_cinema }  # jac:ignore[W2037]
import from core.tenancy.tenant_api { start_shift }  # jac:ignore[W2037]
import from core.catalog.venue_api { create_venue, create_auditorium }  # jac:ignore[W2037]
import from core.catalog.layout_api { save_layout, publish_layout }  # jac:ignore[W2037]
import from core.catalog.movie_api { create_movie }  # jac:ignore[W2037]
import from core.catalog.screening_api { create_screening, schedule_screening, publish_screening }  # jac:ignore[W2037]
import from core.catalog.pricing_api { save_price_list }  # jac:ignore[W2037]
import from core.booking.hold_api { hold_seats }  # jac:ignore[W2037]
import from core.booking.order_api { place_order, my_order }  # jac:ignore[W2037]
import from core.tenancy.open_cinema { open_cinema }
import from core.tenancy.principal { node_id, act_as, restore }
import from core.catalog.venues { find_screening }
import from core.booking.models { Order }

def:pub count_orders(screening_id: str) -> int {
    cinema = open_cinema("nova");
    screening = find_screening(cinema, screening_id);
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = len([screening-->[?:Order]]);
    } finally {
        restore(me);
    }
    return found;
}
""";

def _project -> str {
    workdir = tempfile.mkdtemp(prefix="africinemas-orders-");
    (Path(workdir) / "main.jac").write_text(APP_MAIN);
    shutil.copytree(REPO_ROOT / "core", Path(workdir) / "core");
    (Path(workdir) / "jac.toml").write_text(APP_TOML);
    (Path(workdir) / ".jac").mkdir();
    os.symlink(REPO_ROOT / ".jac" / "venv", Path(workdir) / ".jac" / "venv");
    return workdir;
}

def _held_showtime(server: RealServer) -> str {
    # A priced showtime with A1 held by Anna; returns its id.
    screening = published_showtime(server);
    saved = server.call(
        "save_price_list",
        {
            "tenant": "nova",
            "timezone": "Africa/Nairobi",
            "ticket_types": [{"code": "ADULT", "name": "Adult"}],
            "prices": [{"zone": "", "ticket_type": "ADULT", "price_cents": 80000}],
            "surcharges": [],
            "service_fee_cents": 0
        },
        server.login("owner")
    );
    assert saved["ok"] , saved;
    held = server.call(
        "hold_seats",
        {"slug": "nova", "screening_id": screening, "holder": ANNA, "labels": ["A1"]}
    );
    assert held["ok"] , held;
    return screening;
}

def _place(server: RealServer, screening: str, key: str) -> any {  # jac:ignore[W1037]
    return server.call(
        "place_order",
        {
            "slug": "nova",
            "screening_id": screening,
            "holder": ANNA,
            "idempotency_key": key,
            "items": [{"seat_label": "A1", "ticket_type": "ADULT"}]
        }
    );
}

def _code(result: dict[str, any]) -> str {  # jac:ignore[W1037]
    return "" if result["ok"] else result["error"]["code"];
}

test "one key sent twenty times at once makes one order" {
    workdir = _project();
    server = RealServer(workdir=workdir, env=dict(os.environ));
    try {
        server.start();
        screening = _held_showtime(server);
        key = "order-key-race-xxxxxxxxxxxxxxxx";
        place = lambda (k: str) -> any { return _place(server, screening, k); };
        with ThreadPoolExecutor(max_workers=RACERS) as pool {
            results = list(pool.map(place, [key] * RACERS));
        }
        orders = [
            r["order"]
            for r in results
            if r["ok"]
        ];
        assert orders , [r.get("error") for r in results][:5];
        assert all(o == orders[0] for o in orders) , orders[:3];
        assert all(
            _code(r) == "order_in_progress"
            for r in results
            if not r["ok"]
        ) , [
            r.get("error")
            for r in results
            if not r["ok"]
        ][:5];
        assert server.call("count_orders", {"screening_id": screening}) == 1;
        # Asked again afterwards, every racer gets the one order.
        assert _place(server, screening, key)["order"] == orders[0];
    } finally {
        server.stop(drop=True);
        remove_project(workdir);
    }
}

test "different keys for the same held seats at once still make one order" {
    workdir = _project();
    server = RealServer(workdir=workdir, env=dict(os.environ));
    try {
        server.start();
        screening = _held_showtime(server);
        place = lambda (i: int) -> any { return _place(
            server, screening, f"order-key-{i:04d}-0123456789abcdef"
        ); };
        with ThreadPoolExecutor(max_workers=RACERS) as pool {
            results = list(pool.map(place, range(RACERS)));
        }
        won = [
            r
            for r in results
            if r["ok"]
        ];
        assert len(won) == 1 , [r.get("error") for r in results][:5];
        assert all(
            _code(r) in ["no_hold", "already_ordered"]
            for r in results
            if not r["ok"]
        ) , [
            r.get("error")
            for r in results
            if not r["ok"]
        ][:5];
        assert server.call("count_orders", {"screening_id": screening}) == 1;
    } finally {
        server.stop(drop=True);
        remove_project(workdir);
    }
}
