"""P8.1: the AI agent's tool registry and its privacy filter (core/agent/tools.jac).

The agent can only do what these tools do, so the list is pinned: exactly these tools,
none of them pays, and the tools module reaches no staff code (it imports only the
storefront's and the customer's own modules). Every result is cleaned of private keys,
however deep, before the model sees it.
"""

import re;
import from os { path }
import from core.agent.tools { TOOLS, clean, tool_named }
import from tests.isolation.registry { REGISTRY }

glob TOOLS_FILE: str = path.join(
         path.dirname(path.dirname(path.dirname(path.abspath(__file__)))),
         "core",
         "agent",
         "tools.jac"
     ),
     # The only modules the tools may use: the public storefront and the customer's own.
     ALLOWED: list[str] = [
         "core.catalog.storefront_api",
         "core.catalog.screening_api",
         "core.booking.order_api",
         "core.booking.hold_api",
         "core.booking.customer_tickets",
         "core.tenancy.principal"
     ];

test "exactly these tools, with their scopes, and none of them pays" {
    assert [[fn.__name__, scope] for (fn, scope) in TOOLS]
        == [
            ["find_cinemas", "public"],
            ["whats_on", "public"],
            ["movie_details", "public"],
            ["seat_map", "public"],
            ["ticket_types", "public"],
            ["hold_chosen_seats", "public"],
            ["prepare_order", "public"],
            ["my_bookings", "customer"]
        ];
    for (fn, _) in TOOLS {
        name = fn.__name__;
        assert "pay" not in name and "refund" not in name , name;
    }
    assert tool_named("start_payment") is None and tool_named("whats_on") is not None;
}

test "no tool has an endpoint's name (a same-named function replaces the endpoint, JI-043)" {
    clashes = [
        fn.__name__
        for (fn, _) in TOOLS
        if fn.__name__ in REGISTRY
    ];
    assert clashes == [] , clashes;
}

test "the tools reach only the storefront's and the customer's own code" {
    source = open(TOOLS_FILE).read();
    used = re.findall(r"^import from (core\.[a-z_.]+)", source, re.MULTILINE);
    assert used , "found no imports";
    assert [
        m
        for m in used
        if m not in ALLOWED
    ]
        == [] , used;
    # No staff endpoint by name either.
    for staff in [
        "sell_for_cash",
        "redeem_ticket",
        "audit_log",
        "sales_report",
        "staff_home"
    ] {
        assert staff not in source , staff;
    }
}

test "results lose emails, phones, ticket codes, links, tokens and hold ids, however deep" {
    raw = {
        "ok": True,
        "bookings": [
            {
                "reference": "ABC123",
                "email": "anna@example.com",
                "phone": "254712345678",
                "tickets": [{"seat_label": "A1", "qr": "TKT1.x.y", "link": "/c/x"}],
                "holder": "holder-anna",
                "token": "secret"
            }
        ],
        "hold_id": "h1",
        "idempotency_key": "k"
    };
    cleaned = clean(raw);
    assert cleaned
        == {
            "ok": True,
            "bookings": [{"reference": "ABC123", "tickets": [{"seat_label": "A1"}]}]
        };
    # Long lists are cut short.
    assert len(clean({"rows": list(range(100))})["rows"]) == 20;
}
