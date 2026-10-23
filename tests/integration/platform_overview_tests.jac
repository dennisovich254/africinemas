"""P13.4: the platform overview, across every cinema.

In-process app (payment_app.jac). Anna books two seats at Nova Cinemas (KES 1,860) and
one at Imax Rift (KES 930), both paid today. The platform's overview counts both
cinemas, their states and this week's sign-ups, two bookings and KES 2,790 today, in a
day-by-day list of the last 14 days that adds up to its totals. Each cinema's own sales
report still shows only its own booking. Every platform role reads the overview; a
cinema owner is refused it.
"""

import os;
import uuid;
import from tests.support.served { Served }
import from tests.support.storefront_setup {
    code_of,
    browse,
    open_cinema_for,
    add_movie,
    set_prices,
    add_screening
}
import from tests.support.payment_setup { ANNA, paying_cinema, paid }
import from tests.support.platform_setup { ADMINS_ENV, super_admin, join_platform }

def _book(app: Served, slug: str, screening: str, seats: list[str]) {
    # Anna holds `seats` and orders them as adults.
    held = browse(
        app,
        "hold_seats",
        {"slug": slug, "screening_id": screening, "holder": ANNA, "labels": seats}
    );
    assert held["ok"] , held;
    ordered = browse(
        app,
        "place_order",
        {
            "slug": slug,
            "screening_id": screening,
            "holder": ANNA,
            "idempotency_key": f"order-{uuid.uuid4().hex}",
            "items": [{"seat_label": s, "ticket_type": "ADULT"} for s in seats]
        }
    );
    assert ordered["ok"] , ordered;
}

def _app -> Served {
    (app, _, nova_show) = paying_cinema(["rival"]);
    paid(app, nova_show);
    rift = open_cinema_for(app, "rival", "rift", "Imax Rift");
    add_movie(app, "rival", rift, "Rafiki");
    set_prices(app, "rival", rift);
    rift_show = add_screening(app, "rival", rift, "Rafiki", 0);
    _book(app, "rift", rift_show, ["A1"]);
    paid(app, rift_show, "rift");
    super_admin(app, "boss", "boss@example.com");
    return app;
}

def _close(app: Served) {
    os.environ.pop(ADMINS_ENV, None);
    app.close();
}

def _net(app: Served, who: str, slug: str) -> int {
    # The cinema's own sales report today: its net takings.
    shown = app.call(
        who, "sales_report", {"tenant": slug, "date_from": "", "date_to": ""}
    );
    assert shown["ok"] , shown;
    return shown["report"]["takings"]["net_cents"];
}

test "the overview adds up every cinema's bookings and takings, day by day" {
    app = _app();
    try {
        seen = app.call("boss", "platform_overview");
        assert seen["ok"] , seen;
        assert seen["cinemas"] == 2 and seen["signed_up_this_week"] == 2 , seen;
        states = {s["key"]: s["count"] for s in seen["states"]};
        # Both are live (P14.1): only live cinemas sell.
        assert states["active"] == 2 and states["configuring"] == 0 , states;
        assert seen["bookings"] == 2 , seen;
        assert seen["takings_net_cents"] == 186000 + 93000 , seen;
        assert seen["currency"] == "KES";
        days = seen["days"];
        assert len(days) == 14 and days[0]["start"] == seen["first"];
        assert days[-1]["start"] == seen["last"];
        assert days[-1]["bookings"] == 2 and days[-1]["takings_net_cents"] == 279000;
        assert sum([d["bookings"] for d in days]) == seen["bookings"];
        assert sum([d["takings_net_cents"] for d in days]) == seen["takings_net_cents"];
        # Each cinema's own report has its own booking only.
        assert _net(app, "owner", "nova") == 186000;
        assert _net(app, "rival", "rift") == 93000;
    } finally {
        _close(app);
    }
}

test "every platform role reads the overview; a cinema owner is refused it" {
    app = _app();
    try {
        invited = app.call(
            "boss",
            "invite_platform_member",
            {"email": "rev@example.com", "role": "reviewer"}
        );
        join_platform(app, "rev", invited["token"]);
        assert app.call("rev", "platform_overview")["bookings"] == 2;
        assert code_of(app.call("owner", "platform_overview")) == "not_platform";
    } finally {
        _close(app);
    }
}
