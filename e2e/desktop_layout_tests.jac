"""Desktop layout E2E: the pages fit a laptop and a desktop window.

The phone checks (shell_tests, *_phone checks) run at 375 px, and the 1440 px review
screenshots are full-page, which hides a page that can't scroll. These assert what a
desktop user sees: the landing page scrolls to its footer, and no back-office page
scrolls sideways.
"""

import from e2e.support.web { shared_browser, close_contexts, BASE_URL }
import from e2e.support.api { owner_with_cinema, add_venue, PASSWORD }

glob SIZES: list[tuple[int, int]] = [(1280, 720), (1440, 900)],
     SECTIONS: list[str] = [
         "",
         "reports",
         "venues",
         "screens",
         "movies",
         "screenings",
         "prices",
         "box-office",
         "snacks",
         "scanner",
         "staff",
         "audit",
         "settings"
     ],
     OVERFLOW_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth",
     # The elements reaching past the window's right edge, for the failure message.
     WIDE_JS: str = """() => [...document.querySelectorAll('body *')]
  .filter(e => e.getBoundingClientRect().right > document.documentElement.clientWidth + 1)
  .slice(0, 5)
  .map(e => e.tagName.toLowerCase() + '.' + String(e.className).split(' ').slice(0, 4).join('.')
            + ' (right ' + Math.round(e.getBoundingClientRect().right) + ')')""",
     FOOTER_IN_VIEW_JS: str = """() => { const f = document.querySelector('footer');
  if (!f) return false; const r = f.getBoundingClientRect();
  return r.top >= 0 && r.bottom <= innerHeight + 1; }""";

def _type(page: any, selector: str, value: str) {  # jac:ignore[W1037]
    # Playwright's fill(); the checker mistakes it for JS Array.fill (W6002).
    page.fill(selector, value);  # jac:ignore[W6002]
}

def _no_sideways_scroll(page: any, where: str) {  # jac:ignore[W1037]
    extra = page.evaluate(OVERFLOW_JS);
    assert extra <= 0 , f"{where} scrolls sideways by {extra}px: {page.evaluate(
        WIDE_JS
    )}";
}

test "the landing page scrolls to its footer on a laptop and a desktop" {
    (pw, browser) = shared_browser();
    try {
        for (w, h) in SIZES {
            page = browser.new_context(viewport={"width": w, "height": h}).new_page();
            page.goto(BASE_URL + "/");
            page.wait_for_selector('[data-testid="landing"]');
            _no_sideways_scroll(page, f"landing at {w}x{h}");
            # The keyboard, as a user would: a page that can't scroll never shows the footer.
            page.locator("body").press("End");
            page.wait_for_function(FOOTER_IN_VIEW_JS, timeout=5000);
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "no back-office page scrolls sideways on a laptop or a desktop" {
    owner = owner_with_cinema();
    add_venue(owner);
    (pw, browser) = shared_browser();
    try {
        for (w, h) in SIZES {
            page = browser.new_context(viewport={"width": w, "height": h}).new_page();
            page.goto(BASE_URL + "/login");
            _type(page, "#email", owner["email"]);
            _type(page, "#password", PASSWORD);
            page.click('button[type="submit"]');
            page.wait_for_url("**/app");
            page.wait_for_selector('[data-testid="cinema-list"]');
            _no_sideways_scroll(page, f"the cinema picker at {w}x{h}");
            for section in SECTIONS {
                path = f"/app/{owner['slug']}" + (f"/{section}" if section else "");
                page.goto(BASE_URL + path);
                page.wait_for_selector('[data-testid="app-shell"]');
                page.wait_for_load_state("networkidle");
                _no_sideways_scroll(page, f"{path} at {w}x{h}");
            }
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}
