"""P8.6b: booking from Claude: the booking card's own tools, over MCP with OAuth tokens.

In-process app (tests/apps/payment_app.jac) with the simulated M-Pesa. Nova shows Rafiki
on a five-seat screen; Anna holds and has ordered A1 and A2. Customers sign Claude in
as in P8.6a (tests/integration/oauth_tests.jac).

- The model sees book_showtime (which opens the booking card); the card's own tools
  (card_*) are marked for the card alone (`_meta.ui.visibility: ["app"]`).
- A signed-in customer books through the card: the seats, hold, quote, order and the
  M-Pesa prompt, then the payment settles and the card shows the booking, which is
  saved to the customer (my_bookings lists it). Phone and email never reach the model.
- Signed out, every card tool refuses: sign in first.
- One customer can't take or order another's held seats: each customer's holds and
  orders belong to a holder id the server derives from them.
"""

import json;
import os;
import uuid;
import from urllib.parse { urlencode, urlparse, parse_qs }
import from tests.support.served { Served }
import from tests.support.payment_setup { paying_cinema, settle, fresh_phone }
import from tests.support.storefront_setup { customer_at }

glob VERIFIER: str = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
     CHALLENGE: str = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
     REDIRECT: str = "https://claude.ai/api/mcp/auth_callback",
     EMAIL: str = "kim.books@example.com",
     CARD_TOOLS: list[str] = [
         "card_state",
         "card_hold",
         "card_quote",
         "card_order",
         "card_pay",
         "card_status"
     ];


# The public address these tests expect, whatever a developer's .env says (Jac loads
# .env into test apps too; a tunnel address there would change every URL).
with entry {
    os.environ["AFRICINEMAS_PUBLIC_URL"] = "http://localhost:8000";
}

def _token(app: Served, who: str) -> str {
    # `who` signs Claude in (P8.6a): register, approve, swap the code.
    app.client.set_auth_token("");
    client = json.loads(
        app.client.post(
            "/oauth/register",
            json={"client_name": "Claude", "redirect_uris": [REDIRECT]}
        ).text
    )["client_id"];
    approved = app.call(
        who,
        "oauth_approve",
        {
            "client_id": client,
            "redirect_uri": REDIRECT,
            "code_challenge": CHALLENGE,
            "code_challenge_method": "S256",
            "resource": "http://localhost:8000/c/nova/mcp",
            "scope": "africinemas",
            "state": ""
        }
    );
    code = parse_qs(urlparse(approved["redirect"]).query)["code"][0];
    app.client.set_auth_token("");
    resp = app.client._execute_request(
        "POST",
        "/oauth/token",
        urlencode(
            {
                "grant_type": "authorization_code",
                "code": code,
                "code_verifier": VERIFIER,
                "client_id": client,
                "redirect_uri": REDIRECT
            }
        ).encode(),
        {"Content-Type": "application/x-www-form-urlencoded"}
    );
    return json.loads(resp.text)["access_token"];
}

def _mcp(
    app: Served,
    token: str,
    method: str,
    params: dict[str, any] | None = None  # jac:ignore[W1037]
) -> any {  # jac:ignore[W1037]
    app.client.set_auth_token(token);
    # Nova's own connector: sign-in and booking are per cinema (P8.6c).
    resp = app.client.post(
        "/c/nova/mcp",
        json={"jsonrpc": "2.0", "id": 1, "method": method, "params": params or {}}
    );
    app.client.set_auth_token("");
    assert resp.status_code == 200 , resp.text;
    return json.loads(resp.text);
}

def _tool(
    app: Served,
    token: str,
    name: str,
    args: dict[str, any]  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    got = _mcp(app, token, "tools/call", {"name": name, "arguments": args});
    assert "result" in got , got;
    return got["result"];
}

def _card(
    app: Served,
    token: str,
    name: str,
    args: dict[str, any]  # jac:ignore[W1037]
) -> dict[str, any] {  # jac:ignore[W1037]
    # A card tool's answer, as the card reads it.
    return _tool(app, token, name, args)["structuredContent"];
}

test "the model opens the booking card; the card's tools are the card's alone" {
    (app, _, screening) = paying_cinema([]);
    try {
        customer_at(app, "nova", "kim");
        token = _token(app, "kim");
        tools = {
            t["name"]: t for t in _mcp(app, token, "tools/list")["result"]["tools"]
        };
        opener = tools["book_showtime"];
        assert opener["_meta"]["ui"]["resourceUri"] == "ui://africinemas/booking";
        for name in CARD_TOOLS {
            assert tools[name]["_meta"]["ui"]["visibility"] == ["app"] , name;
        }
        opened = _tool(
            app,
            token,
            "book_showtime",
            {"cinema": "nova", "showtime_id": screening, "seats": ["A2", "A3"]}
        );
        card = opened["structuredContent"];
        assert card["showtime_id"] == screening and card["movie"] == "Rafiki";
        assert card["suggested"] == ["A3"] and card["signed_in"] == True , card;
        assert "card in the chat" in opened["content"][0]["text"];
        # The card resource is there, and frames nothing.
        read = _mcp(app, "", "resources/read", {"uri": "ui://africinemas/booking"});
        html = read["result"]["contents"][0]["text"];
        assert "card_hold" in html and "iframe" not in html.lower();
    } finally {
        app.close();
    }
}

test "a signed-in customer books and pays in the card, and the booking is theirs" {
    (app, _, screening) = paying_cinema([]);
    try {
        customer_at(app, "nova", "kim");
        token = _token(app, "kim");
        where = {"cinema": "nova", "showtime_id": screening};
        state = _card(app, token, "card_state", where);
        assert state["ok"] and state["rows"] == 1 and state["cols"] == 5 , state;
        assert "ADULT" in [t["code"] for t in state["ticket_types"]];
        assert state["hold"] is None and state["order"] is None;
        held = _card(app, token, "card_hold", {** where, "seats": ["A3", "A4"]});
        assert held["ok"] and sorted(held["hold"]["seats"]) == ["A3", "A4"] , held;
        items = [
            {"seat_label": "A3", "ticket_type": "ADULT"},
            {"seat_label": "A4", "ticket_type": "ADULT"}
        ];
        quoted = _card(app, token, "card_quote", {** where, "items": items});
        assert quoted["ok"] and quoted["total"] > 0 , quoted;
        key = f"card-{uuid.uuid4().hex}";
        ordered = _card(
            app, token, "card_order", {** where, "items": items, "key": key}
        );
        assert ordered["ok"] , ordered;
        paying = _card(
            app,
            token,
            "card_pay",
            {** where, "phone": fresh_phone(), "email": EMAIL, "key": f"pay-{key}"}
        );
        assert paying["ok"] and paying["state"] == "stk_requested" , paying;
        # The card's state comes back after a reload, mid-way.
        assert _card(app, token, "card_state", where)["order"] is not None;
        settle(app, screening, paying["reference"]);
        done = _card(app, token, "card_status", where);
        assert done["ok"] and done["state"] == "success" , done;
        assert sorted(done["seats"]) == ["A3", "A4"];
        assert done["email"] and EMAIL not in json.dumps(done);
        # Saved to the customer: Claude's my_bookings lists it, without private details.
        mine = _tool(app, token, "my_bookings", {"cinema": "nova"});
        text = mine["content"][0]["text"];
        assert "A3" in text and EMAIL not in text and "phone" not in text , text;
    } finally {
        app.close();
    }
}

test "signed out, every card tool refuses" {
    (app, _, screening) = paying_cinema([]);
    try {
        for name in CARD_TOOLS {
            got = _card(
                app,
                "",
                name,
                {
                    "cinema": "nova",
                    "showtime_id": screening,
                    "seats": ["A3"],
                    "items": [],
                    "key": "card-0123456789abcdef",
                    "phone": "254700000000",
                    "email": EMAIL
                }
            );
            assert got["ok"] == False and got["code"] == "sign_in" , f"{name}: {got}";
        }
        # The card still opens, and says to sign in.
        opened = _tool(
            app,
            "",
            "book_showtime",
            {"cinema": "nova", "showtime_id": screening, "seats": []}
        );
        assert opened["structuredContent"]["signed_in"] == False;
    } finally {
        app.close();
    }
}

test "one customer can't take or order another's held seats" {
    (app, _, screening) = paying_cinema([]);
    try {
        customer_at(app, "nova", "kim");
        customer_at(app, "nova", "lee");
        where = {"cinema": "nova", "showtime_id": screening};
        kim = _token(app, "kim");
        lee = _token(app, "lee");
        assert _card(app, kim, "card_hold", {** where, "seats": ["A3"]})["ok"];
        taken = _card(app, lee, "card_hold", {** where, "seats": ["A3"]});
        assert taken["ok"] == False , taken;
        # Lee has no hold, so Lee can't order Kim's seat.
        order = _card(
            app,
            lee,
            "card_order",
            {
                ** where,
                "items": [{"seat_label": "A3", "ticket_type": "ADULT"}],
                "key": f"card-{uuid.uuid4().hex}"
            }
        );
        assert order["ok"] == False , order;
        # Lee sees A3 as held, not as Lee's own.
        lee_state = _card(app, lee, "card_state", where);
        a3 = [
            s
            for s in lee_state["seats"]
            if s["label"] == "A3"
        ][0];
        assert a3["state"] == "held" and lee_state["hold"] is None;
    } finally {
        app.close();
    }
}
