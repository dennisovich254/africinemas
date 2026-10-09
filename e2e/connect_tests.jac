"""P8.3 E2E: Settings › AI chat, the cinema's own connector for AI chats.

An owner opens Settings › AI chat and finds the cinema's connector link, a Copy button
and the steps to add it in Claude, on a phone and on a PC, light and dark (screenshots
for review). The link is the real thing: posting MCP's initialize to it answers as that
cinema.
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PROJECTS,
    context_options,
    artifact
}
import from e2e.support.api { PASSWORD, owner_with_cinema }

glob SECTION: str = '[data-testid="connect-section"]',
     LINK: str = '[data-testid="connector-link"]',
     COPY: str = '[data-testid="copy-connector"]',
     OVERFLOW_JS: str = "document.documentElement.scrollWidth - document.documentElement.clientWidth",
     SMALL_TARGETS_JS: str = """() => [...document.querySelectorAll(
    '[data-testid=connect-section] button, [data-testid=connect-section] input, nav[aria-label=Settings] a')]
  .filter(e => { const r = e.getBoundingClientRect(); return r.width > 1 && r.height > 1; })
  .map(e => { const r = e.getBoundingClientRect();
      return {name: (e.getAttribute('aria-label') || e.id || e.textContent).trim().slice(0, 40),
              w: Math.round(r.width), h: Math.round(r.height)}; })
  .filter(t => t.h < 44)""";

def _type(page: any, selector: str, value: str) {  # jac:ignore[W1037]
    # Playwright's fill(); the checker mistakes it for JS Array.fill (W6002).
    page.fill(selector, value);  # jac:ignore[W6002]
}

def _open(
    browser: any,  # jac:ignore[W1037]
    pw: any,  # jac:ignore[W1037]
    project: str,
    owner: dict[str, str],
    scheme: str
) -> any {  # jac:ignore[W1037]
    # Signs in as the owner and opens Settings › AI chat from the Settings tabs.
    page = browser.new_context(**context_options(pw, project, scheme)).new_page();
    page.goto(BASE_URL + "/login");
    _type(page, "#email", owner["email"]);
    _type(page, "#password", PASSWORD);
    page.click('button[type="submit"]');
    page.wait_for_url("**/app");
    page.goto(f"{BASE_URL}/app/{owner['slug']}/settings");
    page.click('[data-testid="settings-tab-ai-chat"]');
    page.wait_for_selector(SECTION);
    return page;
}

test "Settings › AI chat shows the cinema's connector link and how to add it" {
    (pw, browser) = shared_browser();
    try {
        owner = owner_with_cinema("Rupas Cinema");
        for project in PROJECTS {
            for scheme in ["light", "dark"] {
                page = _open(browser, pw, project, owner, scheme);
                link = page.input_value(LINK);
                assert link == f"{BASE_URL}/c/{owner['slug']}/mcp" , link;
                text = page.inner_text(SECTION);
                for words in [
                    "Add custom connector",
                    "No sign-in",
                    "What's on at Rupas Cinema?",
                    "book on your website"
                ] {
                    assert words in text , f"{words} not in {text}";
                }
                page.click(COPY);
                # Copied, or (where the browser won't copy) the link is selected with a note.
                page.wait_for_function(
                    "() => document.querySelector('[data-testid=copy-connector]').textContent === 'Copied'"
                        + " || document.querySelector('[data-testid=connect-section] [aria-live]').textContent.length > 0"
                );
                assert page.evaluate(OVERFLOW_JS) <= 0 , f"{project}: scrolls sideways";
                small = page.evaluate(SMALL_TARGETS_JS);
                assert small == [] , f"{project}: small targets {small}";
                page.screenshot(
                    path=artifact(f"connect-{project}-{scheme}.png"), full_page=True
                );
            }
        }
    } finally {
        close_contexts(browser);
    }
}

test "the connector link answers MCP as that cinema" {
    (pw, browser) = shared_browser();
    try {
        owner = owner_with_cinema("Rupas Cinema");
        page = browser.new_context().new_page();
        answer = page.request.post(
            f"{BASE_URL}/c/{owner['slug']}/mcp",
            data={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {"protocolVersion": "2025-06-18"}
            }
        );
        assert answer.status == 200 , answer.status;
        hello = answer.json();
        assert hello["result"]["serverInfo"]["title"] == "Rupas Cinema" , hello;
        tools = page.request.post(
            f"{BASE_URL}/c/{owner['slug']}/mcp",
            data={"jsonrpc": "2.0", "id": 2, "method": "tools/list"}
        ).json()["result"]["tools"];
        assert "find_cinemas" not in [t["name"] for t in tools];
    } finally {
        close_contexts(browser);
    }
}
