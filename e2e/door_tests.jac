"""17.2b trial S1 E2E: the scanner at /door/<cinema> opens with no connection
(docs/specs/offline-scanner.md §19; core/door/shell.jac, web/door/DoorApp.jac).

On a phone: the worker and manifest are served as themselves, not as the app's page;
the first visit, online, keeps the app's files; then, offline, the page reloads from the
worker and checks a code against the test ticket kept on the device.
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    context_options,
    artifact
}

glob DOOR: str = BASE_URL + "/door/nova",
     APP: str = '[data-testid="door-app"]',
     RESULT: str = '[data-testid="door-result"]',
     # §7.2's test vector, as staff would type it.
     TYPED: str = "7K2M-9QXR-4HJN-P3WD";

def _ready(page: any) {  # jac:ignore[W1037]
    # Every readiness line has an answer, and the worker controls the page.
    page.wait_for_function(
        """() => { const lines = [...document.querySelectorAll('[data-testid="door-check"]')];
          return lines.length >= 5 && lines.every(l => l.dataset.state); }""",
        timeout=60000
    );
    page.wait_for_function("() => !!navigator.serviceWorker.controller", timeout=30000);
}

test "the worker and manifest are served as themselves" {
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(**context_options(pw, "mobile", "light")).new_page();
        worker = page.request.get(BASE_URL + "/door/sw.js");
        assert worker.status == 200 , worker.status;
        assert worker.headers["content-type"].startswith("text/javascript");
        assert worker.headers["service-worker-allowed"] == "/door/";
        assert "door-shell-" in worker.text();
        manifest = page.request.get(BASE_URL + "/door/manifest.webmanifest");
        assert manifest.status == 200 , manifest.status;
        assert manifest.headers["content-type"].startswith("application/manifest+json");
        body = manifest.json();
        assert body["start_url"] == "/door/" and body["scope"] == "/door/" , body;
        # Chrome offers to install only if the manifest's icons load.
        for icon in body["icons"] {
            got = page.request.get(BASE_URL + icon["src"]);
            assert got.status == 200 , (icon["src"], got.status);
        }
    } finally {
        close_contexts(browser);
    }
}

test "after one visit online, the scanner opens and checks a code offline" {
    (pw, browser) = shared_browser();
    try {
        context = browser.new_context(**context_options(pw, "mobile", "light"));
        page = context.new_page();
        page.goto(DOOR);
        page.wait_for_selector(APP);
        _ready(page);
        lines = page.locator('[data-testid="door-check"]');
        for i in range(lines.count()) {
            assert lines.nth(i).get_attribute("data-state") in ["yes", "no"];
        }
        # The files kept, IndexedDB and the hashing agree on any phone; storage that
        # lasts depends on the browser, so it isn't asserted.
        assert lines.nth(0).get_attribute("data-state") == "yes" , lines.nth(
            0
        ).inner_text();
        assert lines.nth(3).get_attribute("data-state") == "yes";
        assert lines.nth(4).get_attribute("data-state") == "yes";
        page.click('[data-testid="door-prepare"]');
        # Offline only once the ticket is saved on the device.
        page.wait_for_selector('[data-testid="door-test-kept"]');

        context.set_offline(True);
        page.reload();
        page.wait_for_selector(APP, timeout=30000);
        page.wait_for_function(
            "() => document.querySelector('[data-testid=\"door-online\"]')?.dataset.online === 'false'"
        );
        page.fill("#door-code", TYPED);  # jac:ignore[W6002]
        page.click('[data-testid="door-check-code"]');
        page.wait_for_selector(RESULT);
        assert page.get_attribute(RESULT, "data-ok") == "true" , page.inner_text(
            RESULT
        );
        assert "F7" in page.inner_text(RESULT);
        page.fill("#door-code", "2222-3333-4444-5555");  # jac:ignore[W6002]
        page.click('[data-testid="door-check-code"]');
        page.wait_for_function(
            "() => document.querySelector('[data-testid=\"door-result\"]').dataset.ok === 'false'"
        );
        page.screenshot(path=artifact("door-offline.png"));
    } finally {
        close_contexts(browser);
    }
}
