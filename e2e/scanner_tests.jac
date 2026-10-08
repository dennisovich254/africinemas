"""P6.4 E2E: checking tickets at the door with the Scanner (simulated M-Pesa).

A showtime starts in an hour, so its door is open, and a guest has paid for A1 and A2
through the public API. The owner signs in and opens Scanner: the one open showtime is
already chosen. A typed reference is admitted, then refused as already used. The camera
path runs through an injected decoder (window.__africinemasDecoder) that "reads" the
codes the test hands it, so scan -> redeem -> result is tested without a camera; without
one, the page says so and typing still works. Review screenshots of the result cards.
"""

import time;
import uuid;
import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PROJECTS,
    context_options,
    artifact
}
import from e2e.support.api { call, PASSWORD }
import from e2e.support.catalog { cinema_selling_tickets }

glob FAKE_DECODER: str = """
window.__africinemasDecoder = {
    available: async () => true,
    start: async (video, onCode) => {
        window.__scan = onCode;
        return () => { window.__scan = null; };
    }
};
""",
     SETTLE_S: int = 30;

def _type(page: any, selector: str, value: str) {  # jac:ignore[W1037]
    # Playwright's fill(); the checker mistakes it for JS Array.fill (W6002).
    page.fill(selector, value);  # jac:ignore[W6002]
}

def _paid_tickets(owner: dict[str, str]) -> list[dict[str, str]] {
    # A guest pays for A1 and A2 through the public API; returns their tickets.
    holder = f"holder-{uuid.uuid4().hex}";
    where = {"slug": owner["slug"], "screening_id": owner["show"], "holder": holder};
    assert call("", "hold_seats", {** where, "labels": ["A1", "A2"]})["ok"];
    ordered = call(
        "",
        "place_order",
        {
            ** where,
            "idempotency_key": f"order-{uuid.uuid4().hex}",
            "items": [
                {"seat_label": "A1", "ticket_type": "ADULT"},
                {"seat_label": "A2", "ticket_type": "ADULT"}
            ]
        }
    );
    assert ordered["ok"] , ordered;
    started = call(
        "",
        "start_payment",
        {
            ** where,
            "phone": "0712345678",
            "email": "guest@example.com",
            "idempotency_key": f"pay-{uuid.uuid4().hex}"
        }
    );
    assert started["ok"] , started;
    deadline = time.time() + SETTLE_S;
    while time.time() < deadline {
        mine = call("", "my_payment", where);
        if mine["ok"] and mine["payment"]["state"] == "success" {
            return mine["payment"]["tickets"];
        }
        time.sleep(1);
    }
    raise AssertionError("the payment never settled");
}

def _open_scanner(page: any, owner: dict[str, str]) {  # jac:ignore[W1037]
    page.goto(BASE_URL + "/login");
    _type(page, "#email", owner["email"]);
    _type(page, "#password", PASSWORD);
    page.click('button[type="submit"]');
    page.wait_for_url("**/app");
    page.goto(f"{BASE_URL}/app/{owner['slug']}/scanner");
    page.wait_for_selector('[data-testid="scanner"]');
}

def _check(page: any, reference: str) -> str {  # jac:ignore[W1037]
    # Types a reference and returns the result card's title.
    before = page.evaluate(
        "document.querySelector('[data-testid=scan-result]')?.dataset.at || ''"
    );
    _type(page, "#ticket-reference", reference);
    page.click('[data-testid="check-ticket"]');
    page.wait_for_function(
        f"document.querySelector('[data-testid=scan-result]')?.dataset.at !== {repr(
            before
        )}"
    );
    return page.inner_text('[data-testid="scan-title"]');
}

test "a typed reference is admitted once, then refused as already used" {
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = cinema_selling_tickets(starts_in_minutes=60);
            tickets = _paid_tickets(owner);
            page = browser.new_context(
                **context_options(pw, project, "light")
            ).new_page();
            _open_scanner(page, owner);
            # The only open showtime is chosen already.
            assert page.get_attribute('[data-testid="door-showtime"]', "aria-pressed")
                == "true";
            assert _check(page, tickets[0]["reference"]) == "Admit";
            assert "Seat A1" in page.inner_text('[data-testid="scan-detail"]');
            assert page.get_attribute('[data-testid="scan-result"]', "data-kind")
                == "admit";
            # Typed again, and in lower case without dashes: the same ticket, used.
            again = tickets[0]["reference"].lower().replace("-", "");
            assert _check(page, again) == "Already used";
            assert "Scanned at" in page.inner_text('[data-testid="scan-detail"]');
            assert _check(page, "not a ticket") == "Not a ticket";
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "the camera path: scanned codes are redeemed through the decoder" {
    owner = cinema_selling_tickets(starts_in_minutes=60);
    tickets = _paid_tickets(owner);
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(**context_options(pw, "mobile", "light")).new_page();
        page.add_init_script(FAKE_DECODER);
        _open_scanner(page, owner);
        page.locator('[data-testid="start-camera"]').tap();
        page.wait_for_selector('[data-testid="stop-camera"]');
        page.wait_for_function("typeof window.__scan === 'function'");
        page.evaluate(f"window.__scan({repr(tickets[1]['qr'])})");
        page.wait_for_selector('[data-testid="scan-result"][data-kind="admit"]');
        assert "Seat A2" in page.inner_text('[data-testid="scan-detail"]');
        # The same ticket held in front of the camera again at once counts once: the
        # card still says Admit.
        page.evaluate(f"window.__scan({repr(tickets[1]['qr'])})");
        page.wait_for_timeout(1500);
        assert page.inner_text('[data-testid="scan-title"]') == "Admit";
        page.evaluate("window.__scan('TKT1.NOTASIGNEDCODE.XXXXXXXX')");
        page.wait_for_selector('[data-testid="scan-result"][data-kind="refuse"]');
        assert page.inner_text('[data-testid="scan-title"]') == "Not a ticket";
        page.locator('[data-testid="stop-camera"]').tap();
        page.wait_for_function("window.__scan === null");
    } finally {
        close_contexts(browser);
    }
}

test "without a camera, the page says so and typing still works" {
    owner = cinema_selling_tickets(starts_in_minutes=60);
    tickets = _paid_tickets(owner);
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            **context_options(pw, "desktop", "light")
        ).new_page();
        page.add_init_script(
            "window.__africinemasDecoder = {available: async () => false, start: async () => () => {}};"
        );
        _open_scanner(page, owner);
        page.click('[data-testid="start-camera"]');
        page.wait_for_selector('[data-testid="camera-unavailable"]');
        assert _check(page, tickets[0]["reference"]) == "Admit";
    } finally {
        close_contexts(browser);
    }
}

test "review screenshots of the scanner" {
    (pw, browser) = shared_browser();
    try {
        for scheme in ["light", "dark"] {
            for project in PROJECTS {
                owner = cinema_selling_tickets(starts_in_minutes=60);
                tickets = _paid_tickets(owner);
                page = browser.new_context(
                    **context_options(pw, project, scheme), reduced_motion="reduce"
                ).new_page();
                page.add_init_script(FAKE_DECODER);
                _open_scanner(page, owner);
                _check(page, tickets[0]["reference"]);
                page.evaluate("document.fonts.ready");
                page.screenshot(
                    path=artifact(f"scanner-admit-{project}-{scheme}.png"),
                    full_page=True
                );
                _check(page, tickets[0]["reference"]);
                page.screenshot(
                    path=artifact(f"scanner-refused-{project}-{scheme}.png"),
                    full_page=True
                );
                page.context.close();
            }
        }
    } finally {
        close_contexts(browser);
    }
}
