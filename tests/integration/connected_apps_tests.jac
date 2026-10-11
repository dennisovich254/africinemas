"""P8.6d: a customer sees the apps they've let book for them at a cinema, and disconnects them.

In-process app (tests/apps/payment_app.jac). Each app a customer signs in (Claude, through
our OAuth provider) is a connection at that cinema: its own chat account, its tokens,
and when it was connected. The customer lists them on the cinema's storefront
(my_connected_apps) and can disconnect one (disconnect_app): at once, its access token
stops working and its refresh token is refused, and other apps keep working. Only the
cinema's own customer account sees or ends its connections.
"""

import from tests.support.served { Served }
import from tests.support.storefront_setup { code_of, customer_at, open_cinema_for }
import from tests.support.payment_setup { paying_cinema }
import from tests.support.oauth_flow { signed_in, mcp_call, refresh }

def _tool_names(app: Served, token: str) -> list[str] {
    return [t["name"] for t in mcp_call(app, token, "tools/list")["result"]["tools"]];
}

def _status(app: Served, token: str) -> int {
    # The HTTP status of an MCP call with `token`.
    app.client.set_auth_token(token);
    resp = app.client.post(
        "/c/nova/mcp", json={"jsonrpc": "2.0", "id": 1, "method": "tools/list"}
    );
    app.client.set_auth_token("");
    return resp.status_code;
}

def _apps(app: Served, who: str, slug: str = "nova") -> any {  # jac:ignore[W1037]
    return app.call(who, "my_connected_apps", {"slug": slug});
}

def _disconnect(app: Served, who: str, app_id: str, slug: str = "nova") -> any {  # jac:ignore[W1037]
    return app.call(who, "disconnect_app", {"slug": slug, "app_id": app_id});
}

test "a customer sees the app they connected, with the cinema and when" {
    (app, _, _) = paying_cinema([]);
    try {
        customer_at(app, "nova", "kim");
        assert _apps(app, "kim")["apps"] == [];
        (client, _) = signed_in(app, "kim");
        listed = _apps(app, "kim");
        assert listed["ok"] , listed;
        assert len(listed["apps"]) == 1 , listed;
        one = listed["apps"][0];
        assert one["app_id"] == client and one["name"] == "Claude" , one;
        assert one["connected_at"] , one;
    } finally {
        app.close();
    }
}

test "disconnecting an app ends its access and refresh at once, and only its own" {
    (app, _, _) = paying_cinema([]);
    try {
        customer_at(app, "nova", "kim");
        (first, first_tokens) = signed_in(app, "kim");
        (second, second_tokens) = signed_in(app, "kim");
        assert first != second;
        assert len(_apps(app, "kim")["apps"]) == 2;
        for tokens in [first_tokens, second_tokens] {
            assert "my_bookings" in _tool_names(app, tokens["access_token"]);
        }
        assert _disconnect(app, "kim", first)["ok"];
        # The first app is signed out: Jac refuses its token (its account is gone), and
        # its refresh is refused.
        assert _status(app, first_tokens["access_token"]) == 401;
        assert refresh(app, first, first_tokens["refresh_token"])["error"]
            == "invalid_grant";
        # The second app still works, and refreshes.
        assert "my_bookings" in _tool_names(app, second_tokens["access_token"]);
        renewed = refresh(app, second, second_tokens["refresh_token"]);
        assert "my_bookings" in _tool_names(app, renewed["access_token"]) , renewed;
        assert [a["app_id"] for a in _apps(app, "kim")["apps"]] == [second];
        # Disconnecting it again finds nothing.
        assert code_of(_disconnect(app, "kim", first)) == "not_found";
    } finally {
        app.close();
    }
}

test "signing the same app in again keeps one connection" {
    (app, _, _) = paying_cinema([]);
    try {
        customer_at(app, "nova", "kim");
        (client, tokens) = signed_in(app, "kim");
        renewed = refresh(app, client, tokens["refresh_token"]);
        assert "access_token" in renewed , renewed;
        assert len(_apps(app, "kim")["apps"]) == 1;
    } finally {
        app.close();
    }
}

test "only the cinema's own customer sees or ends their connections" {
    (app, _, _) = paying_cinema([]);
    try {
        open_cinema_for(app, "owner", "rift", "Rift Cinemas");
        customer_at(app, "nova", "kim");
        customer_at(app, "nova", "lee");
        customer_at(app, "rift", "riftfan");
        (client, tokens) = signed_in(app, "kim");
        # Another customer sees none of Kim's, and can't end them.
        assert _apps(app, "lee")["apps"] == [];
        assert code_of(_disconnect(app, "lee", client)) == "not_found";
        # Staff and other cinemas' customers aren't Nova's customers at all.
        for who in ["owner", "riftfan"] {
            assert code_of(_apps(app, who)) == "not_your_cinema" , who;
            assert code_of(_disconnect(app, who, client)) == "not_your_cinema" , who;
        }
        # Kim's account at Rift doesn't exist; nothing of Kim's is listed there.
        assert "my_bookings" in _tool_names(app, tokens["access_token"]);
    } finally {
        app.close();
    }
}
