"""P3.7b E2E: the screenings programme (Screenings page) and the price list (Prices page).

Staff who create showtimes pick a screen, add screenings (a movie and a start time),
publish them to the storefront, move, unpublish and cancel them. The server's draft and
scheduled states are both "Not published" here. Staff who manage settings set the ticket
types, prices per seat zone, time-of-day extras and the service fee.
"""

import from datetime { datetime, timedelta }
import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PROJECTS,
    context_options,
    artifact
}
import from e2e.support.api {
    PASSWORD,
    call,
    owner_with_cinema,
    add_venue,
    add_screen,
    add_staff
}

glob PROGRAMME: str = '[data-testid="screenings-page"]',
     PRICES: str = '[data-testid="prices-page"]',
     CONFIRM: str = '[data-testid="confirm-delete"]',
     ROW: str = '[data-testid="screening"]',
     OVERFLOW_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth",
     SMALL_TARGETS_JS: str = """() => [...document.querySelectorAll(
    'a[href], button, [role=button], input, select, textarea')]
  .filter(e => { const r = e.getBoundingClientRect(); return r.width > 1 && r.height > 1
      && getComputedStyle(e).visibility !== 'hidden'; })
  .map(e => { const r = e.getBoundingClientRect();
      return {name: (e.getAttribute('aria-label') || e.id || e.textContent).trim().slice(0, 40),
              w: Math.round(r.width), h: Math.round(r.height)}; })
  .filter(t => t.w < 44 || t.h < 44)""",
     UNLABELLED_JS: str = """() => [...document.querySelectorAll('input:not([type=hidden]), textarea, select')]
  .filter(e => !(e.labels && e.labels.length) && !e.getAttribute('aria-label')
      && !e.getAttribute('aria-labelledby'))
  .map(e => e.id || e.name || e.outerHTML.slice(0, 60))""",
     HEADINGS_JS: str = "[...document.querySelectorAll('h1,h2,h3,h4')].map(h => +h.tagName[1])";

def _type(page: any, selector: str, value: str) {  # jac:ignore[W1037]
    # Playwright's fill(); the checker mistakes it for JS Array.fill (W6002).
    page.fill(selector, value);  # jac:ignore[W6002]
}

def _page(browser: any, pw: any, project: str, scheme: str = "light") -> any {  # jac:ignore[W1037]
    # Pinned to Nairobi time, so typed times mean the same instant on every machine.
    options = context_options(pw, project, scheme);
    options["timezone_id"] = "Africa/Nairobi";
    return browser.new_context(**options).new_page();
}

def _sign_in(page: any, email: str) {  # jac:ignore[W1037]
    page.goto(BASE_URL + "/login");
    _type(page, "#email", email);
    _type(page, "#password", PASSWORD);
    page.click('button[type="submit"]');
    page.wait_for_url("**/app");
}

def _open(page: any, slug: str, section: str, ready: str) {  # jac:ignore[W1037]
    page.goto(f"{BASE_URL}/app/{slug}/{section}");
    page.wait_for_selector(ready);
}

def _day(days_ahead: int) -> str {
    # A date in YYYY-MM-DD, days from now.
    return (datetime.now() + timedelta(days=days_ahead)).strftime("%Y-%m-%d");
}

def _cinema(with_layout: bool = True) -> dict[str, str] {
    # A cinema with a venue, a screen (with a published seat layout) and a movie.
    owner = owner_with_cinema();
    venue = add_venue(owner, "Westgate");
    screen = add_screen(owner, venue, "Screen 1");
    if with_layout {
        seats = [
            {"label": "A1", "row": 0, "col": 0},
            {"label": "A2", "row": 0, "col": 1},
            {"label": "A3", "row": 0, "col": 2, "seat_type": "VIP", "zone": "Gold"}
        ];
        assert call(
            owner["token"],
            "save_layout",
            {
                "tenant": owner["slug"],
                "auditorium_id": screen,
                "rows": 1,
                "cols": 3,
                "seats": seats
            }
        )["ok"];
        assert call(
            owner["token"],
            "publish_layout",
            {"tenant": owner["slug"], "auditorium_id": screen}
        )["ok"];
    }
    owner["screen"] = screen;
    owner["venue"] = venue;
    owner["movie"] = call(
        owner["token"],
        "create_movie",
        {
            "tenant": owner["slug"],
            "title": "Rafiki",
            "synopsis": "",
            "runtime_minutes": 83,
            "age_rating": "18",
            "genres": ["Drama"],
            "language": ""
        }
    )["movie"]["movie_id"];
    return owner;
}

def _screening_at(owner: dict[str, str], day: str, clock: str, publish: bool) -> str {
    made = call(
        owner["token"],
        "create_screening",
        {
            "tenant": owner["slug"],
            "auditorium_id": owner["screen"],
            "movie_id": owner["movie"],
            "starts_at": f"{day}T{clock}:00+03:00"
        }
    );
    assert made["ok"] , made;
    sid = made["screening"]["screening_id"];
    if publish {
        for step in ["schedule_screening", "publish_screening"] {
            assert call(
                owner["token"], step, {"tenant": owner["slug"], "screening_id": sid}
            )["ok"];
        }
    }
    return sid;
}

def _add_screening(page: any, day: str, clock: str) {  # jac:ignore[W1037]
    page.click('button:has-text("Add screening")');
    page.select_option("#screening-movie", label="Rafiki");
    _type(page, "#screening-date", day);
    _type(page, "#screening-time", clock);
    page.click('button:has-text("Create screening")');
}

test "a screening is added, published and appears on the storefront" {
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = _cinema();
            page = _page(browser, pw, project);
            _sign_in(page, owner["email"]);
            _open(page, owner["slug"], "screenings", PROGRAMME);
            assert page.is_visible('text="No screenings on Screen 1 yet"');
            assert page.locator("#screening-movie").count() == 0 , "the form starts folded";
            _add_screening(page, _day(2), "19:30");
            row = page.locator(ROW, has_text="Rafiki");
            row.wait_for();
            assert "19:30" in row.inner_text();
            assert row.locator('[data-testid="screening-state"]').inner_text()
                == "Not published";
            row.locator('button:has-text("Publish")').click();
            row.locator(
                '[data-testid="screening-state"]:text-is("On the storefront")'
            ).wait_for();
            page.goto(f"{BASE_URL}/c/{owner['slug']}");
            page.wait_for_selector('[data-testid="storefront"] li:has-text("Rafiki")');
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "clashing and past start times are refused under the start time" {
    owner = _cinema();
    _screening_at(owner, _day(3), "18:00", False);
    (pw, browser) = shared_browser();
    try {
        page = _page(browser, pw, "desktop");
        _sign_in(page, owner["email"]);
        _open(page, owner["slug"], "screenings", PROGRAMME);
        _add_screening(page, _day(3), "18:30");
        page.wait_for_selector('#screening-time-error[role="alert"]');
        assert "already has" in page.inner_text("#screening-time-error");
        assert page.get_attribute("#screening-time", "aria-describedby")
            == "screening-time-error";
        _type(page, "#screening-date", _day(-1));
        page.click('button:has-text("Create screening")');
        page.wait_for_selector('#screening-time-error:has-text("future")');
    } finally {
        close_contexts(browser);
    }
}

test "a screen without a published seat layout says what to do" {
    owner = _cinema(with_layout=False);
    (pw, browser) = shared_browser();
    try {
        page = _page(browser, pw, "mobile");
        _sign_in(page, owner["email"]);
        _open(page, owner["slug"], "screenings", PROGRAMME);
        _add_screening(page, _day(2), "19:30");
        page.wait_for_selector('[role="alert"]:has-text("seat layout")');
        assert page.locator(
            f'a[href="/app/{owner["slug"]}/screens/{owner["screen"]}"]'
        ).count()
            == 1 , "a link to the screen's layout";
    } finally {
        close_contexts(browser);
    }
}

test "a screening is unpublished, moved and cancelled" {
    owner = _cinema();
    _screening_at(owner, _day(4), "14:00", True);
    (pw, browser) = shared_browser();
    try {
        page = _page(browser, pw, "desktop");
        _sign_in(page, owner["email"]);
        _open(page, owner["slug"], "screenings", PROGRAMME);
        row = page.locator(ROW, has_text="Rafiki");
        row.locator(
            '[data-testid="screening-state"]:text-is("On the storefront")'
        ).wait_for();
        assert row.locator('button:has-text("Move")').count() == 0 , "published times are fixed";
        row.locator('button:has-text("Unpublish")').click();
        row.locator(
            '[data-testid="screening-state"]:text-is("Not published")'
        ).wait_for();
        row.locator('button:has-text("Move")').click();
        _type(page, 'input[id^="move-time-"]', "16:45");
        row.locator('button:has-text("Save time")').click();
        page.wait_for_selector(f'{ROW}:has-text("16:45")');
        row.locator('button:has-text("Cancel screening")').click();
        page.wait_for_selector(CONFIRM);
        page.click(f'{CONFIRM} button:has-text("Cancel screening")');
        row.locator('[data-testid="screening-state"]:text-is("Cancelled")').wait_for();
        assert row.locator("button").count() == 0 , "nothing more to do with a cancelled one";
    } finally {
        close_contexts(browser);
    }
}

test "an owner sets ticket types, prices by zone, a time-of-day extra and a fee" {
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = owner_with_cinema();
            page = _page(browser, pw, project);
            _sign_in(page, owner["email"]);
            _open(page, owner["slug"], "prices", PRICES);
            assert page.input_value("#ticket-name-0") == "Adult";
            _type(page, "#price-0-0", "800");
            page.click('button:has-text("Add ticket type")');
            _type(page, "#ticket-name-1", "Child");
            _type(page, "#price-0-1", "500");
            page.click('button:has-text("Add zone")');
            _type(page, "#zone-name-1", "Gold");
            _type(page, "#price-1-0", "1200");
            page.click('button:has-text("Add time-of-day extra")');
            _type(page, "#surcharge-name-0", "Evening");
            _type(page, "#surcharge-start-0", "18:00");
            _type(page, "#surcharge-end-0", "00:00");
            _type(page, "#surcharge-amount-0", "100");
            _type(page, "#service-fee", "30");
            page.click('button:has-text("Save prices")');
            page.wait_for_selector('[data-testid="prices-message"]:has-text("Saved")');
            saved = call(owner["token"], "get_price_list", {"tenant": owner["slug"]})[
                "price_list"
            ];
            assert [t["name"] for t in saved["ticket_types"]]
                == ["Adult", "Child"] , saved;
            cells = {
                (p["zone"], p["ticket_type"]): p["price_cents"] for p in saved["prices"]
            };
            assert cells
                == {
                    ("", "ADULT"): 80000,
                    ("", "CHILD"): 50000,
                    ("Gold", "ADULT"): 120000
                } , cells;
            evening = saved["surcharges"][0];
            assert (evening["start"], evening["end"], evening["amount_cents"])
                == ("18:00", "24:00", 10000) , evening;
            assert evening["days"] == [0, 1, 2, 3, 4, 5, 6];
            assert saved["service_fee_cents"] == 3000;
            page.reload();
            page.wait_for_selector(PRICES);
            assert page.input_value("#price-1-0") == "1200";
            assert page.input_value("#zone-name-1") == "Gold";
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "a price list with problems is refused and every problem is listed" {
    owner = owner_with_cinema();
    (pw, browser) = shared_browser();
    try {
        page = _page(browser, pw, "desktop");
        _sign_in(page, owner["email"]);
        _open(page, owner["slug"], "prices", PRICES);
        _type(page, "#price-0-0", "800");
        page.click('button:has-text("Add time-of-day extra")');
        _type(page, "#surcharge-name-0", "Backwards");
        _type(page, "#surcharge-start-0", "20:00");
        _type(page, "#surcharge-end-0", "18:00");
        _type(page, "#surcharge-amount-0", "50");
        page.click('button[aria-pressed="true"]:has-text("Sun")');
        page.click('button:has-text("Save prices")');
        page.wait_for_selector('[data-testid="price-problems"][role="alert"]');
        assert "Backwards" in page.inner_text('[data-testid="price-problems"]');
        assert call(owner["token"], "get_price_list", {"tenant": owner["slug"]})[
            "price_list"
        ]
            is None , "nothing saved";
    } finally {
        close_contexts(browser);
    }
}

test "box office staff see neither the Screenings nor the Prices pages" {
    owner = _cinema();
    agent = add_staff(owner, "box_office_agent", owner["venue"]);
    assert call(agent["token"], "start_shift", {"tenant": owner["slug"]})["ok"];
    (pw, browser) = shared_browser();
    try {
        page = _page(browser, pw, "desktop");
        _sign_in(page, agent["email"]);
        page.goto(f"{BASE_URL}/app/{owner['slug']}");
        page.wait_for_selector('[data-testid="shell-sidebar"]');
        nav = [
            n.strip()
            for n in page.locator(
                '[data-testid="shell-sidebar"] nav a'
            ).all_inner_texts()
        ];
        assert "Screenings" not in nav and "Prices" not in nav , nav;
        page.goto(f"{BASE_URL}/app/{owner['slug']}/prices");
        page.wait_for_selector('[data-testid="no-access"]');
    } finally {
        close_contexts(browser);
    }
}

test "the Screenings and Prices pages pass the phone checks" {
    owner = _cinema();
    _screening_at(owner, _day(2), "19:30", True);
    _screening_at(owner, _day(3), "14:00", False);
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            viewport={"width": 375, "height": 812},
            is_mobile=True,
            has_touch=True,
            timezone_id="Africa/Nairobi"
        ).new_page();
        _sign_in(page, owner["email"]);
        for (path, ready) in [("screenings", PROGRAMME), ("prices", PRICES)] {
            _open(page, owner["slug"], path, ready);
            if path == "prices" {
                page.click('button:has-text("Add time-of-day extra")');
            }
            assert page.evaluate(OVERFLOW_JS) <= 0 , f"{path} scrolls sideways";
            assert page.evaluate(SMALL_TARGETS_JS) == [] , f"{path}: {page.evaluate(
                SMALL_TARGETS_JS
            )}";
            assert page.evaluate(UNLABELLED_JS) == [] , f"{path}: {page.evaluate(
                UNLABELLED_JS
            )}";
            assert "jac:ignore" not in page.inner_text("body") , f"{path}: a code comment shows";
            levels = page.evaluate(HEADINGS_JS);
            assert levels.count(1) == 1 , f"{path}: {levels}";
            assert all(b - a <= 1 for (a, b) in zip(levels, levels[1:])) , f"{path}: {levels}";
        }
    } finally {
        close_contexts(browser);
    }
}

test "review screenshots of the Screenings and Prices pages" {
    owner = _cinema();
    _screening_at(owner, _day(2), "19:30", True);
    _screening_at(owner, _day(2), "15:00", False);
    _screening_at(owner, _day(3), "21:00", True);
    call(
        owner["token"],
        "save_price_list",
        {
            "tenant": owner["slug"],
            "timezone": "Africa/Nairobi",
            "ticket_types": [
                {"code": "ADULT", "name": "Adult"},
                {"code": "CHILD", "name": "Child"}
            ],
            "prices": [
                {"zone": "", "ticket_type": "ADULT", "price_cents": 80000},
                {"zone": "", "ticket_type": "CHILD", "price_cents": 50000},
                {"zone": "Gold", "ticket_type": "ADULT", "price_cents": 120000}
            ],
            "surcharges": [
                {
                    "name": "Evening",
                    "days": [0, 1, 2, 3, 4, 5, 6],
                    "start": "18:00",
                    "end": "24:00",
                    "amount_cents": 10000
                }
            ],
            "service_fee_cents": 3000
        }
    );
    (pw, browser) = shared_browser();
    try {
        for scheme in ["light", "dark"] {
            for width in [375, 768, 1440] {
                page = browser.new_context(
                    viewport={"width": width, "height": 900},
                    color_scheme=scheme,
                    timezone_id="Africa/Nairobi"
                ).new_page();
                _sign_in(page, owner["email"]);
                for (path, ready, name) in [
                    ("screenings", PROGRAMME, "screenings"),
                    ("prices", PRICES, "prices")
                ] {
                    _open(page, owner["slug"], path, ready);
                    page.evaluate("document.fonts.ready");
                    page.screenshot(
                        path=artifact(f"{name}-{width}-{scheme}.png"), full_page=True
                    );
                }
                page.context.close();
            }
        }
    } finally {
        close_contexts(browser);
    }
}
