"""P3.7a E2E: managing venues (Venues page), screens (Screens page) and movies (Movies page).

Staff who configure venues add, edit and delete venues on the Venues page, and add,
rename and delete each venue's screens on the Screens page; everyone else who reads seat
plans sees the screens without those controls, and no Venues page.
Staff who create movies add them on the Movies page, edit their details and upload a
poster. Deleting anything asks first, and the server's refusals (a venue that still has
screens, a name already taken) are shown next to what they concern.
"""

import io;
import from PIL { Image }
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
     VENUES: str = '[data-testid="venues-page"]',
     SCREENS: str = '[data-testid="screens-page"]',
     MOVIES: str = '[data-testid="movies-page"]',
     MOVIE_FORM: str = '[data-testid="movie-form"]',
     CONFIRM: str = '[data-testid="confirm-delete"]',
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
    return browser.new_context(**context_options(pw, project, scheme)).new_page();
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

def _poster_png -> bytes {
    out = io.BytesIO();
    Image.new("RGB", (400, 600), "#7A2E3B").save(out, format="PNG");
    return out.getvalue();
}

def _venue(page: any, name: str) -> any {  # jac:ignore[W1037]
    # The venue's card on the Venues page, or its group on the Screens page.
    return page.locator(f'[data-testid="venue"]:has(h2:text-is("{name}"))');
}

test "an owner adds a venue and a screen, renames the screen and opens its layout" {
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = owner_with_cinema();
            page = _page(browser, pw, project);
            _sign_in(page, owner["email"]);
            _open(page, owner["slug"], "venues", VENUES);
            assert page.is_visible('text="No venues yet"');
            # The add forms stay folded away until asked for.
            assert page.locator("#new-venue-name").count() == 0;
            page.click('button:has-text("Add venue")');
            assert page.evaluate("document.activeElement.id") == "new-venue-name";
            _type(page, "#new-venue-name", "Westgate");
            _type(page, "#new-venue-city", "Nairobi");
            page.click('button:has-text("Create venue")');
            venue = _venue(page, "Westgate");
            venue.wait_for();
            assert "Nairobi" in venue.inner_text();
            page.wait_for_selector("#new-venue-name", state="detached");
            # Its screens are on the Screens page.
            venue.locator('a:has-text("Screens")').click();
            page.wait_for_selector(SCREENS);
            venue = _venue(page, "Westgate");
            venue.wait_for();
            assert venue.locator('input[id^="new-screen-"]').count() == 0;
            venue.locator('button:has-text("Add screen")').click();
            venue.locator('input[id^="new-screen-"]').fill("Screen 1");  # jac:ignore[W6002]
            venue.locator('button:has-text("Create screen")').click();
            venue.locator('[data-testid="screen-name"]:text-is("Screen 1")').wait_for();
            venue.locator('input[id^="new-screen-"]').wait_for(state="detached");
            venue.locator('button[aria-label="Rename Screen 1"]').click();
            venue.locator('input[id^="screen-name-"]').fill("IMAX");  # jac:ignore[W6002]
            venue.locator('button:has-text("Save name")').click();
            venue.locator('[data-testid="screen-name"]:text-is("IMAX")').wait_for();
            venue.locator('a:has([data-testid="screen-name"])').click();
            page.wait_for_selector(f"{TITLE}:has-text('Seat layout')");
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "venue changes show the server's refusals next to what they concern" {
    owner = owner_with_cinema();
    venue_id = add_venue(owner, "Westgate");
    add_screen(owner, venue_id, "Screen 1");
    (pw, browser) = shared_browser();
    try {
        page = _page(browser, pw, "desktop");
        _sign_in(page, owner["email"]);
        _open(page, owner["slug"], "venues", VENUES);
        # A name that's taken is flagged under the name field, and the form stays open.
        page.click('button:has-text("Add venue")');
        _type(page, "#new-venue-name", "westgate");
        page.click('button:has-text("Create venue")');
        page.wait_for_selector('#new-venue-name-error[role="alert"]');
        assert "already" in page.inner_text("#new-venue-name-error");
        assert page.get_attribute("#new-venue-name", "aria-describedby")
            == "new-venue-name-error";
        # Cancel folds it away again.
        page.click('[data-testid="add-venue"] button:has-text("Cancel")');
        page.wait_for_selector("#new-venue-name", state="detached");
        # A venue with screens can't be deleted: asked first, then told why.
        page.click('button[aria-label="Delete Westgate"]');
        page.wait_for_selector(CONFIRM);
        page.click(f'{CONFIRM} button:has-text("Delete venue")');
        page.wait_for_selector('[role="alert"]:has-text("screens")');
        assert _venue(page, "Westgate").is_visible();
        # Editing a venue's details.
        page.click('button[aria-label="Edit Westgate"]');
        _type(page, 'input[id^="venue-city-"]', "Nairobi West");
        page.click('button:has-text("Save venue")');
        page.wait_for_selector('[data-testid="venue"]:has-text("Nairobi West")');
        # An empty screen can be deleted: after a Cancel, then a confirmed delete.
        _open(page, owner["slug"], "screens", SCREENS);
        page.click('button[aria-label="Delete Screen 1"]');
        page.click(f'{CONFIRM} button:has-text("Cancel")');
        page.wait_for_selector(CONFIRM, state="detached");
        page.click('button[aria-label="Delete Screen 1"]');
        page.click(f'{CONFIRM} button:has-text("Delete screen")');
        page.wait_for_selector('[data-testid="screen-name"]', state="detached");
    } finally {
        close_contexts(browser);
    }
}

test "staff who only read seat plans see screens without the controls, and no Venues page" {
    owner = owner_with_cinema();
    venue_id = add_venue(owner, "Westgate");
    add_screen(owner, venue_id, "Screen 1");
    agent = add_staff(owner, "box_office_agent", venue_id);
    assert call(agent["token"], "start_shift", {"tenant": owner["slug"]})["ok"];
    (pw, browser) = shared_browser();
    try {
        page = _page(browser, pw, "desktop");
        _sign_in(page, agent["email"]);
        _open(page, owner["slug"], "screens", SCREENS);
        page.wait_for_selector('[data-testid="screen-name"]:text-is("Screen 1")');
        assert page.locator('button:has-text("Add venue")').count() == 0;
        assert page.locator('button:has-text("Add screen")').count() == 0;
        assert page.locator('button[aria-label^="Delete"]').count() == 0;
        assert page.locator('button[aria-label^="Rename"]').count() == 0;
        nav = [
            n.strip()
            for n in page.locator(
                '[data-testid="shell-sidebar"] nav a'
            ).all_inner_texts()
        ];
        assert "Movies" not in nav and "Venues" not in nav , nav;
    } finally {
        close_contexts(browser);
    }
}

test "an owner adds a movie, fixes a mistake, uploads its poster and edits it" {
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = owner_with_cinema();
            page = _page(browser, pw, project);
            _sign_in(page, owner["email"]);
            _open(page, owner["slug"], "movies", MOVIES);
            assert page.is_visible('text="No movies yet"');
            page.click('a:has-text("Add movie")');
            page.wait_for_selector(MOVIE_FORM);
            _type(page, "#movie-title", "Rafiki");
            _type(page, "#movie-synopsis", "Two young women in Nairobi fall in love.");
            _type(page, "#movie-runtime", "0");
            page.locator("#movie-runtime").blur();
            page.wait_for_selector('#movie-runtime-error[role="alert"]');
            assert page.get_attribute("#movie-runtime", "aria-describedby")
                == "movie-runtime-error";
            _type(page, "#movie-runtime", "83");
            page.select_option("#movie-rating", "18");
            _type(page, "#movie-genres", "Drama, Romance");
            _type(page, "#movie-language", "English, Swahili");
            page.click('button:has-text("Add movie")');
            page.wait_for_url(f"**/app/{owner['slug']}/movies/*");
            page.wait_for_selector("#poster-file");
            page.set_input_files(
                "#poster-file",
                files=[
                    {
                        "name": "rafiki.png",
                        "mimeType": "image/png",
                        "buffer": _poster_png()
                    }
                ]
            );
            page.wait_for_selector('[data-testid="poster"]');
            _type(page, "#movie-runtime", "84");
            page.click('button:has-text("Save changes")');
            page.wait_for_selector('[role="status"]:has-text("Saved")');
            _open(page, owner["slug"], "movies", MOVIES);
            row = page.locator('[data-testid="movie-list"] li', has_text="Rafiki");
            assert "84 min" in row.inner_text() and "18" in row.inner_text();
            row.locator('img[data-testid="movie-poster"]').wait_for();
            page.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "deleting a movie asks first" {
    owner = owner_with_cinema();
    movie = call(
        owner["token"],
        "create_movie",
        {
            "tenant": owner["slug"],
            "title": "Supa Modo",
            "synopsis": "",
            "runtime_minutes": 74,
            "age_rating": "GE",
            "genres": [],
            "language": ""
        }
    )["movie"]["movie_id"];
    (pw, browser) = shared_browser();
    try {
        page = _page(browser, pw, "mobile");
        _sign_in(page, owner["email"]);
        _open(page, owner["slug"], f"movies/{movie}", MOVIE_FORM);
        page.click('button:has-text("Delete movie")');
        page.wait_for_selector(CONFIRM);
        page.click(f'{CONFIRM} button:has-text("Delete Supa Modo")');
        page.wait_for_url(f"**/app/{owner['slug']}/movies");
        page.wait_for_selector('text="No movies yet"');
    } finally {
        close_contexts(browser);
    }
}

test "the Screens and Movies pages pass the phone checks" {
    owner = owner_with_cinema();
    venue_id = add_venue(owner, "Westgate");
    add_screen(owner, venue_id, "Screen 1");
    movie = call(
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
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            viewport={"width": 375, "height": 812}, is_mobile=True, has_touch=True
        ).new_page();
        _sign_in(page, owner["email"]);
        for (path, ready) in [
            ("venues", VENUES),
            ("screens", SCREENS),
            ("movies", MOVIES),
            ("movies/new", MOVIE_FORM),
            (f"movies/{movie}", MOVIE_FORM)
        ] {
            _open(page, owner["slug"], path, ready);
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

test "review screenshots of the Screens and Movies pages" {
    owner = owner_with_cinema();
    for (name, city) in [("Westgate", "Nairobi"), ("Nyali Centre", "Mombasa")] {
        venue_id = add_venue(owner, name);
        call(
            owner["token"],
            "update_venue",
            {
                "tenant": owner["slug"],
                "venue_id": venue_id,
                "name": name,
                "city": city,
                "address": ""
            }
        );
        add_screen(owner, venue_id, "Screen 1");
        add_screen(owner, venue_id, "IMAX");
    }
    movie = "";
    for (title, minutes, rating) in [("Rafiki", 83, "18"), ("Supa Modo", 74, "GE")] {
        movie = call(
            owner["token"],
            "create_movie",
            {
                "tenant": owner["slug"],
                "title": title,
                "synopsis": "A Kenyan film.",
                "runtime_minutes": minutes,
                "age_rating": rating,
                "genres": ["Drama"],
                "language": "Swahili"
            }
        )["movie"]["movie_id"];
    }
    (pw, browser) = shared_browser();
    try {
        for scheme in ["light", "dark"] {
            for width in [375, 768, 1440] {
                page = browser.new_context(
                    viewport={"width": width, "height": 900}, color_scheme=scheme
                ).new_page();
                _sign_in(page, owner["email"]);
                for (path, ready, name) in [
                    ("venues", VENUES, "venues"),
                    ("screens", SCREENS, "screens"),
                    ("movies", MOVIES, "movies"),
                    (f"movies/{movie}", MOVIE_FORM, "movie-edit")
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
