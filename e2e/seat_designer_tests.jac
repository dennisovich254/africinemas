"""P3.3 E2E: the seat layout designer (desktop) and its read-only preview (phone).

The designer paints a grid: pick a seat type, click (or drag across) cells; empty cells
are aisles. Seats are labelled automatically (row letter + seat number, counted left to
right, skipping aisles). Saving writes a draft; publishing freezes it (P3.2). Phones and
staff who may only read seat plans see a read-only preview.
"""

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

glob TITLE: str = '[data-testid="shell-title"]',
     DESIGNER: str = '[data-testid="seat-designer"]',
     GRID: str = '[data-testid="seat-grid"]',
     STATUS: str = '[data-testid="layout-status"]',
     MESSAGE: str = '[data-testid="save-message"]',
     NOTICE: str = '[data-testid="larger-screen-notice"]',
     OVERFLOW_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth";

def _type(page: any, selector: str, value: str) {  # jac:ignore[W1037]
    # Playwright's fill(); the checker mistakes it for JS Array.fill (W6002).
    page.fill(selector, value);  # jac:ignore[W6002]
}

def _setup(role: str = "") -> dict[str, str] {
    # A cinema with one venue and one screen; with `role`, also a staff member to sign
    # in as (their email is in "email").
    owner = owner_with_cinema();
    venue = add_venue(owner);
    owner["screen"] = add_screen(owner, venue);
    owner["venue"] = venue;
    if role {
        staff = add_staff(owner, role, venue);
        assert call(staff["token"], "start_shift", {"tenant": owner["slug"]})["ok"];
        owner["email"] = staff["email"];
    }
    return owner;
}

def _open_designer(
    browser: any,
    pw: any,
    project: str,
    owner: dict[str, str],
    scheme: str = "light"  # jac:ignore[W1037]
) -> any {  # jac:ignore[W1037]
    page = browser.new_context(**context_options(pw, project, scheme)).new_page();
    errors: list[str] = [];
    page.on("pageerror", lambda (e: any) { errors.append(str(e)); });  # jac:ignore[W1037]
    page.on(
        "console",
        lambda (m: any) { errors.append(m.text) if m.type == "error" else None; }  # jac:ignore[W1037]
    );
    page.goto(BASE_URL + "/login");
    _type(page, "#email", owner["email"]);
    _type(page, "#password", PASSWORD);
    page.click('button[type="submit"]');
    page.wait_for_url("**/app");
    # Every account here already has an open shift (staff actions and reads need one).
    page.goto(f"{BASE_URL}/app/{owner['slug']}/screens");
    page.click(f'a[href="/app/{owner["slug"]}/screens/{owner["screen"]}"]');
    try {
        page.wait_for_selector(DESIGNER);
    } except Exception as e {
        # Say why the designer didn't appear: a render error, or what's on screen instead.
        shown = page.inner_text("body")[:300];
        raise AssertionError(
            f"designer didn't appear. errors: {errors}; page: {shown!r}"
        ) from e;
    }
    return page;
}

def _cell(r: int, c: int) -> str {
    return f'{GRID} [data-cell="{r}:{c}"]';
}

def _cells(page: any) -> dict[str, str] {  # jac:ignore[W1037]
    # Every cell's seat type ("" for an aisle), keyed "row:col".
    return page.evaluate(
        """g => Object.fromEntries([...document.querySelectorAll(g + ' [data-cell]')]
            .map(e => [e.dataset.cell, e.dataset.seatType || '']))""",
        GRID
    );
}

def _pick(page: any, seat_type: str) {  # jac:ignore[W1037]
    page.click(f'[data-testid="seat-tools"] [data-tool="{seat_type}"]');
}

def _size(page: any, rows: int, cols: int) {  # jac:ignore[W1037]
    _type(page, "#layout-rows", str(rows));
    _type(page, "#layout-cols", str(cols));
    page.locator("#layout-cols").blur();
    page.wait_for_selector(_cell(rows - 1, cols - 1));
}

test "an owner builds a 5 x 8 layout with an aisle and wheelchair spaces, publishes it, and a reload shows it unchanged" {
    (pw, browser) = shared_browser();
    try {
        owner = _setup();
        page = _open_designer(browser, pw, "desktop", owner);
        current = page.locator('[data-testid="shell-sidebar"] a[aria-current="page"]');
        assert current.inner_text().strip() == "Screens" , "the designer is part of Screens";
        _size(page, 5, 8);
        _pick(page, "STANDARD");
        for r in range(4) {
            for c in range(8) {
                if c != 3 {
                    page.click(_cell(r, c));
                }
            }
        }
        _pick(page, "WHEELCHAIR");
        for c in [0, 1] {
            page.click(_cell(4, c));
        }
        assert page.locator(_cell(0, 3)).get_attribute("data-seat-type") == "" , "column 4 is the aisle";
        assert page.locator(_cell(0, 4)).get_attribute("aria-label").startswith("A4") , "labels skip the aisle";
        page.click('button:has-text("Save draft")');
        page.wait_for_selector(f'{MESSAGE}:has-text("Draft saved")');
        page.click('button:has-text("Publish")');
        page.click('button:has-text("Publish version 1")');
        page.wait_for_selector(f'{STATUS}:has-text("Published")');
        before = _cells(page);
        page.reload();
        page.wait_for_selector(DESIGNER);
        assert _cells(page) == before , "the reloaded layout is identical";
        assert "version 1" in page.locator(STATUS).inner_text();
        listed = call(
            owner["token"],
            "list_layouts",
            {"tenant": owner["slug"], "auditorium_id": owner["screen"]}
        );
        assert listed["published_version"] == 1 , listed;
        layout = call(
            owner["token"],
            "get_layout",
            {"tenant": owner["slug"], "layout_id": listed["layouts"][0]["layout_id"]}
        )["layout"];
        assert (layout["rows"], layout["cols"], len(layout["seats"]))
            == (5, 8, 30) , layout;
        row_a = [
            s["label"]
            for s in layout["seats"]
            if s["row"] == 0
        ];
        assert row_a == ["A1", "A2", "A3", "A4", "A5", "A6", "A7"] , row_a;
        assert [
            (s["label"], s["seat_type"])
            for s in layout["seats"]
            if s["row"] == 4
        ]
            == [("E1", "WHEELCHAIR"), ("E2", "WHEELCHAIR")];
    } finally {
        close_contexts(browser);
    }
}

test "the grid works with the keyboard alone" {
    (pw, browser) = shared_browser();
    try {
        owner = _setup();
        page = _open_designer(browser, pw, "desktop", owner);
        _size(page, 2, 3);
        page.locator(_cell(0, 0)).focus();
        page.keyboard.press("Enter");
        page.keyboard.press("ArrowRight");
        page.keyboard.press("ArrowRight");
        page.keyboard.press(" ");
        page.keyboard.press("ArrowDown");
        page.keyboard.press("Enter");
        assert page.evaluate("document.activeElement.dataset.cell") == "1:2";
        cells = _cells(page);
        assert [
            k
            for k in sorted(cells)
            if cells[k]
        ]
            == ["0:0", "0:2", "1:2"] , cells;
        # One Tab stop for the whole grid: Tab leaves it.
        page.keyboard.press("Tab");
        assert page.evaluate("document.activeElement.dataset.cell || ''") == "";
    } finally {
        close_contexts(browser);
    }
}

test "a click on a seat of the selected type removes it, and the counts follow" {
    (pw, browser) = shared_browser();
    try {
        owner = _setup();
        page = _open_designer(browser, pw, "desktop", owner);
        _size(page, 1, 3);
        _pick(page, "VIP");
        for c in range(3) {
            page.click(_cell(0, c));
        }
        page.click(_cell(0, 1));
        assert _cells(page) == {"0:0": "VIP", "0:1": "", "0:2": "VIP"};
        assert "2 seats" in page.locator('[data-testid="seat-count"]').inner_text();
    } finally {
        close_contexts(browser);
    }
}

test "editing a published layout saves the next version, and the old one is kept" {
    (pw, browser) = shared_browser();
    try {
        owner = _setup();
        page = _open_designer(browser, pw, "desktop", owner);
        _size(page, 1, 2);
        page.click(_cell(0, 0));
        page.click('button:has-text("Save draft")');
        page.wait_for_selector(f'{MESSAGE}:has-text("Draft saved")');
        page.click('button:has-text("Publish")');
        page.click('button:has-text("Publish version 1")');
        page.wait_for_selector(f'{STATUS}:has-text("Published")');
        page.click(_cell(0, 1));
        assert "version 2" in page.locator('[data-testid="unsaved-note"]').inner_text();
        page.click('button:has-text("Save draft")');
        page.wait_for_selector(f'{STATUS}:has-text("Draft")');
        assert "version 2" in page.locator(STATUS).inner_text();
        listed = call(
            owner["token"],
            "list_layouts",
            {"tenant": owner["slug"], "auditorium_id": owner["screen"]}
        );
        assert [(l["version"], l["status"], l["seat_count"]) for l in listed["layouts"]]
            == [(1, "published", 1), (2, "draft", 2)] , listed;
    } finally {
        close_contexts(browser);
    }
}

test "publishing asks for confirmation and can be cancelled" {
    (pw, browser) = shared_browser();
    try {
        owner = _setup();
        page = _open_designer(browser, pw, "desktop", owner);
        _size(page, 1, 1);
        page.click(_cell(0, 0));
        page.click('button:has-text("Save draft")');
        page.wait_for_selector(f'{MESSAGE}:has-text("Draft saved")');
        page.click('button:has-text("Publish")');
        page.click('[data-testid="publish-confirm"] button:has-text("Cancel")');
        assert "Draft" in page.locator(STATUS).inner_text();
        listed = call(
            owner["token"],
            "list_layouts",
            {"tenant": owner["slug"], "auditorium_id": owner["screen"]}
        );
        assert listed["published_version"] is None , listed;
    } finally {
        close_contexts(browser);
    }
}

test "phones get a read-only preview and a larger-screen notice" {
    (pw, browser) = shared_browser();
    try {
        owner = _setup();
        call(
            owner["token"],
            "save_layout",
            {
                "tenant": owner["slug"],
                "auditorium_id": owner["screen"],
                "rows": 2,
                "cols": 12,
                "seats": [{"label": f"A{c + 1}", "row": 0, "col": c} for c in range(12)]
            }
        );
        page = _open_designer(browser, pw, "mobile", owner);
        assert page.locator(NOTICE).is_visible();
        assert page.locator('[data-testid="seat-tools"]').count() == 0;
        assert page.locator('button:has-text("Save draft")').count() == 0;
        assert page.locator(f"{GRID} button").count() == 0 , "preview cells aren't controls";
        assert page.evaluate(OVERFLOW_JS) <= 0 , "the page doesn't scroll sideways";
        assert page.locator(GRID).get_attribute("aria-label").startswith("Seat layout");
        # Preview seats are small enough that a 12-seat row fits a phone without scrolling.
        (grid_width, viewport) = page.evaluate(
            "g => [document.querySelector(g).getBoundingClientRect().width, innerWidth]",
            GRID
        );
        assert grid_width <= viewport - 32 , f"preview is {grid_width}px on a {viewport}px phone";
    } finally {
        close_contexts(browser);
    }
}

test "staff who can only read seat plans see the preview on desktop too" {
    (pw, browser) = shared_browser();
    try {
        owner = _setup("box_office_agent");
        page = _open_designer(browser, pw, "desktop", owner);
        assert page.locator('[data-testid="seat-tools"]').count() == 0;
        assert page.locator('button:has-text("Save draft")').count() == 0;
        assert "can't change"
            in page.locator('[data-testid="read-only-note"]').inner_text();
    } finally {
        close_contexts(browser);
    }
}

test "the Screens section lists each venue's screens, for staff who read seat plans" {
    (pw, browser) = shared_browser();
    try {
        owner = _setup();
        add_screen(owner, owner["venue"], "IMAX");
        for project in PROJECTS {
            page = _open_designer(browser, pw, project, owner);
            page.goto(f"{BASE_URL}/app/{owner['slug']}/screens");
            page.wait_for_selector('[data-testid="screens-list"]');
            names = page.locator(
                '[data-testid="screens-list"] li [data-testid="screen-name"]'
            ).all_inner_texts();
            assert [n.strip() for n in names] == ["IMAX", "Screen 1"] , names;
            assert page.locator(TITLE).inner_text().strip() == "Screens";
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "review screenshots of the designer and the phone preview" {
    (pw, browser) = shared_browser();
    try {
        owner = _setup();
        seats = [];
        for r in range(6) {
            for c in range(12) {
                if c not in (3, 8) {
                    kind = "PREMIUM" if r >= 4 else "STANDARD";
                    seats.append({"label": "x", "row": r, "col": c, "seat_type": kind});
                }
            }
        }
        seats = seats
            + [
                {"label": "w1", "row": 7, "col": 0, "seat_type": "WHEELCHAIR"},
                {"label": "w2", "row": 7, "col": 1, "seat_type": "COMPANION"},
                {"label": "b1", "row": 7, "col": 11, "seat_type": "BLOCKED"}
            ];
        for (i, s) in enumerate(seats) {
            s["label"] = f"S{i + 1}";
        }
        call(
            owner["token"],
            "save_layout",
            {
                "tenant": owner["slug"],
                "auditorium_id": owner["screen"],
                "rows": 8,
                "cols": 12,
                "seats": seats
            }
        );
        for scheme in ["light", "dark"] {
            for (project, width) in [
                ("desktop", 1440),
                ("desktop", 768),
                ("mobile", 375)
            ] {
                page = _open_designer(browser, pw, project, owner, scheme);
                if width == 768 {
                    page.set_viewport_size({"width": 768, "height": 900});
                }
                page.evaluate("document.fonts.ready");
                page.screenshot(
                    path=artifact(f"designer-{width}-{scheme}.png"), full_page=True
                );
                page.context.close();
            }
        }
    } finally {
        close_contexts(browser);
    }
}
