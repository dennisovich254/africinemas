"""P8.6d E2E: a customer's account page, and disconnecting an app that can book for them.

A customer signs up on the storefront and opens Account from the header: no apps yet,
so the page shows the cinema's connector address to add in Claude. An app then signs
in for them (the OAuth flow Claude follows, sent from here: register, approve as the
customer, swap the code); the page lists it with when it was connected. Disconnect asks
first in the row; "Keep it" changes nothing, and Disconnect ends it: the row goes, the
page says so, and the app's token is refused (401). Phone and PC, light and dark
(screenshots for review).
"""

import from e2e.support.web {
    shared_browser,
    close_contexts,
    BASE_URL,
    PROJECTS,
    context_options,
    artifact
}
import from e2e.support.api { call, unique, email_for, PASSWORD }
import from e2e.support.catalog { cinema_selling_tickets }
import from tests.support.real_server { http_call }

glob VERIFIER: str = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
     CHALLENGE: str = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
     REDIRECT: str = "https://claude.ai/api/mcp/auth_callback";

def _type(page: any, selector: str, value: str) {  # jac:ignore[W1037]
    # Playwright's fill(); the checker mistakes it for JS Array.fill (W6002).
    page.fill(selector, value);  # jac:ignore[W6002]
}

def _sign_up(page: any, slug: str) {  # jac:ignore[W1037]
    # A new customer account at the cinema, signed in, back on its home page.
    page.goto(f"{BASE_URL}/c/{slug}/sign-up?next=/c/{slug}");
    page.wait_for_selector('[data-testid="customer-sign-up"]');
    _type(page, "#name", "Kim");
    _type(page, "#email", email_for(unique("kim")));
    _type(page, "#password", PASSWORD);
    page.click('[data-testid="customer-sign-up"] button[type="submit"]');
    page.wait_for_function("!!localStorage.getItem('jac_token')");
    page.wait_for_url(f"**/c/{slug}");
}

def _connect_app(customer_token: str, slug: str) -> str {
    # What Claude does to sign in for the customer; returns the app's access token.
    (_, doc) = http_call(
        "GET", f"{BASE_URL}/.well-known/oauth-protected-resource/c/{slug}/mcp"
    );
    resource = str(doc["resource"]);
    (status, made) = http_call(
        "POST",
        f"{BASE_URL}/oauth/register",
        {
            "client_name": "Claude",
            "redirect_uris": [REDIRECT],
            "token_endpoint_auth_method": "none"
        }
    );
    assert status == 200 and made.get("client_id") , made;
    client_id = str(made["client_id"]);
    approved = call(
        customer_token,
        "oauth_approve",
        {
            "client_id": client_id,
            "redirect_uri": REDIRECT,
            "code_challenge": CHALLENGE,
            "code_challenge_method": "S256",
            "resource": resource,
            "scope": "africinemas",
            "state": ""
        }
    );
    assert approved["ok"] , approved;
    code = str(approved["redirect"]).split("code=")[1].split("&")[0];
    (status, tokens) = http_call(
        "POST",
        f"{BASE_URL}/oauth/token",
        {
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": VERIFIER,
            "client_id": client_id,
            "redirect_uri": REDIRECT,
            "resource": resource
        }
    );
    assert status == 200 and tokens.get("access_token") , tokens;
    return str(tokens["access_token"]);
}

def _mcp_status(slug: str, token: str) -> int {
    (status, _) = http_call(
        "POST",
        f"{BASE_URL}/c/{slug}/mcp",
        {"jsonrpc": "2.0", "id": 1, "method": "tools/list"},
        token
    );
    return status;
}

test "a customer disconnects an app from their account page" {
    owner = cinema_selling_tickets();
    slug = owner["slug"];
    (pw, browser) = shared_browser();
    try {
        page = browser.new_context(**context_options(pw, "mobile", "light")).new_page();
        _sign_up(page, slug);
        # The account page from the menu; no apps yet, so how to connect Claude.
        page.locator('[data-testid="storefront-menu"]').tap();
        page.locator(
            '[data-testid="storefront-menu-sheet"] [data-testid="account-page"]'
        ).tap();
        page.wait_for_selector('[data-testid="account"]');
        address = page.inner_text('[data-testid="connector-address"]');
        assert address.endswith(f"/c/{slug}/mcp") , address;
        # Claude signs in for them; the page lists it.
        token = _connect_app(page.evaluate("localStorage.getItem('jac_token')"), slug);
        assert _mcp_status(slug, token) == 200;
        page.reload();
        row = page.wait_for_selector('[data-testid="connected-app"]');
        assert "Claude" in row.inner_text() and "Connected" in row.inner_text();
        # "Keep it" changes nothing.
        page.locator('[data-testid="disconnect-app"]').tap();
        page.get_by_role("button", name="Keep it").tap();
        assert page.locator('[data-testid="connected-app"]').count() == 1;
        assert _mcp_status(slug, token) == 200;
        # Disconnect ends it, here and for the app.
        page.locator('[data-testid="disconnect-app"]').tap();
        page.locator('[data-testid="confirm-disconnect"]').tap();
        page.wait_for_selector('[data-testid="no-connected-apps"]');
        assert "Claude is disconnected"
            in page.inner_text('[data-testid="account-note"]');
        assert _mcp_status(slug, token) == 401;
    } finally {
        close_contexts(browser);
    }
}

test "review screenshots of the account page" {
    (pw, browser) = shared_browser();
    try {
        for scheme in ["light", "dark"] {
            for project in PROJECTS {
                owner = cinema_selling_tickets();
                slug = owner["slug"];
                page = browser.new_context(
                    **context_options(pw, project, scheme), reduced_motion="reduce"
                ).new_page();
                _sign_up(page, slug);
                page.goto(f"{BASE_URL}/c/{slug}/account");
                page.wait_for_selector('[data-testid="no-connected-apps"]');
                page.evaluate("document.fonts.ready");
                page.screenshot(
                    path=artifact(f"account-empty-{project}-{scheme}.png"),
                    full_page=True
                );
                _connect_app(page.evaluate("localStorage.getItem('jac_token')"), slug);
                page.reload();
                page.wait_for_selector('[data-testid="connected-app"]');
                page.click('[data-testid="disconnect-app"]');
                page.wait_for_selector('[data-testid="confirm-disconnect"]');
                page.screenshot(
                    path=artifact(f"account-disconnect-{project}-{scheme}.png"),
                    full_page=True
                );
                page.context.close();
            }
        }
    } finally {
        close_contexts(browser);
    }
}
