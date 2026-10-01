"""P3.7c E2E: the Staff page and joining a cinema from an invitation link.

An owner invites someone with a role (optionally limited to a venue) and a note on who
it's for, and shares the link. The invitee opens it, signs in (or creates an account)
and accepts. The owner then sees them by name, changes their role, disables them (their
next action is refused), re-enables and removes them; removing asks first.
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
    email_for,
    unique,
    register,
    owner_with_cinema,
    add_venue,
    add_staff
}

glob STAFF: str = '[data-testid="staff-page"]',
     ROW: str = '[data-testid="member"]',
     CONFIRM: str = '[data-testid="confirm-delete"]',
     INVITE_PAGE: str = '[data-testid="invite-page"]',
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

def _sign_in(page: any, email: str, then: str = "**/app") {  # jac:ignore[W1037]
    _type(page, "#email", email);
    _type(page, "#password", PASSWORD);
    page.click('button[type="submit"]');
    page.wait_for_url(then);
}

def _open_staff(page: any, slug: str) {  # jac:ignore[W1037]
    page.goto(f"{BASE_URL}/app/{slug}/staff");
    page.wait_for_selector(STAFF);
}

def _member(page: any, text: str) -> any {  # jac:ignore[W1037]
    return page.locator(ROW, has_text=text);
}

def _invite(page: any, role: str, venue: str, note: str) -> str {  # jac:ignore[W1037]
    # Makes an invitation on the Staff page; returns the link to share.
    page.click('button:has-text("Invite someone")');
    page.select_option("#invite-role", label=role);
    if venue {
        page.select_option("#invite-venue", label=venue);
    }
    _type(page, "#invite-note", note);
    page.click('button:has-text("Create invitation")');
    page.wait_for_selector("#invite-link");
    return page.input_value("#invite-link");
}

test "an owner invites a box-office agent who joins from the link, then manages them" {
    (pw, browser) = shared_browser();
    try {
        for project in PROJECTS {
            owner = owner_with_cinema();
            add_venue(owner, "Westgate");
            invitee = email_for(unique("agent"));
            register(invitee);
            page = _page(browser, pw, project);
            page.goto(BASE_URL + "/login");
            _sign_in(page, owner["email"]);
            _open_staff(page, owner["slug"]);
            you = _member(page, "You");
            assert "Owner" in you.inner_text() and owner["email"] in you.inner_text();
            assert you.locator("button").count() == 0 , "nobody manages their own membership";
            link = _invite(page, "Box office agent", "Westgate", "Wanjiru");
            assert link.startswith(f"{BASE_URL}/invite/") , link;
            # The invitee, in their own browser: signs in from the link and joins.
            guest = _page(browser, pw, project);
            guest.goto(link);
            guest.wait_for_selector(INVITE_PAGE);
            guest.click('a:has-text("Sign in")');
            _sign_in(guest, invitee, "**/invite/**");
            guest.click('button:has-text("Accept invitation")');
            guest.wait_for_url(f"**/app/{owner['slug']}");
            # The owner sees them by name and note, and changes their role.
            _open_staff(page, owner["slug"]);
            row = _member(page, invitee);
            row.wait_for();
            assert "Wanjiru" in row.inner_text();
            assert "Box office agent (Westgate)" in row.inner_text();
            row.locator('button:has-text("Change role")').click();
            page.select_option('select[id^="role-for-"]', label="Usher");
            row.locator('button:has-text("Save role")').click();
            page.wait_for_selector(
                f'{ROW}:has-text("{invitee}"):has-text("Usher (Westgate)")'
            );
            # Disabled: their next action is refused.
            row.locator('button:has-text("Disable")').click();
            row.locator('[data-testid="member-status"]:text-is("Disabled")').wait_for();
            guest.goto(f"{BASE_URL}/app/{owner['slug']}");
            guest.wait_for_selector('[data-testid="cinema-not-found"]');
            row.locator('button:has-text("Enable")').click();
            row.locator('[data-testid="member-status"]:text-is("Active")').wait_for();
            # Removing asks first.
            row.locator('button:has-text("Remove")').click();
            page.wait_for_selector(CONFIRM);
            page.click(f'{CONFIRM} button:has-text("Remove from staff")');
            page.wait_for_selector(f'{ROW}:has-text("{invitee}")', state="detached");
            page.context.close();
            guest.context.close();
        }
    } finally {
        close_contexts(browser);
    }
}

test "someone new creates an account from the invitation and joins" {
    owner = owner_with_cinema();
    invite = call(
        owner["token"],
        "invite_staff",
        {"tenant": owner["slug"], "role": "usher", "venue_id": "", "label": "Otieno"}
    );
    assert invite["ok"] , invite;
    newcomer = email_for(unique("newcomer"));
    (pw, browser) = shared_browser();
    try {
        page = _page(browser, pw, "mobile");
        page.goto(f"{BASE_URL}/invite/{invite['token']}");
        page.wait_for_selector(INVITE_PAGE);
        page.click('a:has-text("Create an account")');
        page.wait_for_selector("#email");
        _type(page, "#email", newcomer);
        _type(page, "#password", PASSWORD);
        if page.locator("#confirm-password").count() > 0 {
            _type(page, "#confirm-password", PASSWORD);
        }
        page.click('button[type="submit"]');
        page.wait_for_url("**/invite/**");
        page.click('button:has-text("Accept invitation")');
        page.wait_for_url(f"**/app/{owner['slug']}");
        staff = call(owner["token"], "list_staff", {"tenant": owner["slug"]})["staff"];
        joined = [
            s
            for s in staff
            if s["label"] == "Otieno"
        ];
        assert len(joined) == 1 and joined[0]["email"] == newcomer , staff;
    } finally {
        close_contexts(browser);
    }
}

test "a used or broken invitation link says so" {
    member = email_for(unique("member"));
    register(member);
    (pw, browser) = shared_browser();
    try {
        page = _page(browser, pw, "desktop");
        page.goto(BASE_URL + "/login");
        _sign_in(page, member);
        page.goto(f"{BASE_URL}/invite/not-a-real-token");
        page.click('button:has-text("Accept invitation")');
        page.wait_for_selector(
            '[role="alert"]:has-text("expired or was already used")'
        );
    } finally {
        close_contexts(browser);
    }
}

test "staff without the right to manage staff don't see the Staff page" {
    owner = owner_with_cinema();
    agent = add_staff(owner, "box_office_agent");
    assert call(agent["token"], "start_shift", {"tenant": owner["slug"]})["ok"];
    (pw, browser) = shared_browser();
    try {
        page = _page(browser, pw, "desktop");
        page.goto(BASE_URL + "/login");
        _sign_in(page, agent["email"]);
        page.goto(f"{BASE_URL}/app/{owner['slug']}");
        page.wait_for_selector('[data-testid="shell-sidebar"]');
        nav = [
            n.strip()
            for n in page.locator(
                '[data-testid="shell-sidebar"] nav a'
            ).all_inner_texts()
        ];
        assert "Staff" not in nav , nav;
    } finally {
        close_contexts(browser);
    }
}

def _phone_checks(page: any, name: str) {  # jac:ignore[W1037]
    assert page.evaluate(OVERFLOW_JS) <= 0 , f"{name} scrolls sideways";
    assert page.evaluate(SMALL_TARGETS_JS) == [] , f"{name}: {page.evaluate(
        SMALL_TARGETS_JS
    )}";
    assert page.evaluate(UNLABELLED_JS) == [] , f"{name}: {page.evaluate(
        UNLABELLED_JS
    )}";
    assert "jac:ignore" not in page.inner_text("body") , f"{name}: a code comment shows";
    levels = page.evaluate(HEADINGS_JS);
    assert levels.count(1) == 1 , f"{name}: {levels}";
    assert all(b - a <= 1 for (a, b) in zip(levels, levels[1:])) , f"{name}: {levels}";
}

test "the Staff and invitation pages pass the phone checks" {
    owner = owner_with_cinema();
    add_venue(owner, "Westgate");
    add_staff(owner, "usher");
    invite = call(
        owner["token"],
        "invite_staff",
        {"tenant": owner["slug"], "role": "usher", "venue_id": ""}
    )["token"];
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(
            viewport={"width": 375, "height": 812}, is_mobile=True, has_touch=True
        ).new_page();
        page.goto(f"{BASE_URL}/invite/{invite}");
        page.wait_for_selector(INVITE_PAGE);
        _phone_checks(page, "invite, signed out");
        page.goto(BASE_URL + "/login");
        _sign_in(page, owner["email"]);
        _open_staff(page, owner["slug"]);
        page.click('button:has-text("Invite someone")');
        page.wait_for_selector("#invite-role");
        _phone_checks(page, "staff");
    } finally {
        close_contexts(browser);
    }
}

test "review screenshots of the Staff and invitation pages" {
    owner = owner_with_cinema();
    venue = add_venue(owner, "Westgate");
    add_staff(owner, "box_office_agent", venue);
    add_staff(owner, "usher");
    invite = call(
        owner["token"],
        "invite_staff",
        {"tenant": owner["slug"], "role": "usher", "venue_id": ""}
    )["token"];
    (pw, browser) = shared_browser();
    try {
        for scheme in ["light", "dark"] {
            for width in [375, 768, 1440] {
                page = browser.new_context(
                    viewport={"width": width, "height": 900}, color_scheme=scheme
                ).new_page();
                page.goto(f"{BASE_URL}/invite/{invite}");
                page.wait_for_selector(INVITE_PAGE);
                page.evaluate("document.fonts.ready");
                page.screenshot(path=artifact(f"invite-{width}-{scheme}.png"));
                page.goto(BASE_URL + "/login");
                _sign_in(page, owner["email"]);
                _open_staff(page, owner["slug"]);
                page.click('button:has-text("Invite someone")');
                page.select_option("#invite-role", label="Box office agent");
                page.evaluate("document.fonts.ready");
                page.screenshot(
                    path=artifact(f"staff-{width}-{scheme}.png"), full_page=True
                );
                page.context.close();
            }
        }
    } finally {
        close_contexts(browser);
    }
}
