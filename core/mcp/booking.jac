"""The booking card's own tools (P8.6b): booking from Claude, through the website's endpoints.

Claude's model only opens the card (book_showtime, core/mcp/server.jac). The card then
calls these tools itself; they're marked for the card alone (`_meta.ui.visibility:
["app"]`), so the model never sees or calls them, and never sees what they return:

- card_state: the seat map, ticket types, and this customer's hold, order and payment
  for the showtime (so the card picks up where it was);
- card_hold, card_quote, card_order: hold the tapped seats, price the tickets, place
  the order (hold_seats, quote_hold, place_order);
- card_pay: the M-Pesa prompt to the customer's phone (start_payment); they enter their
  PIN there, never anywhere else;
- card_status: the payment, and once paid, the booking saved to the customer
  (save_for_caller, as them), so it shows in their bookings and on My tickets.

Signed in only (an OAuth token for the customer's chat account, P8.6a): signed out,
every tool says to sign in. Each customer's holds and orders belong to a holder id
the server derives from them (holder_for), never one a caller sends, so one customer
can't touch another's. Answers carry no phone number and only a masked email.
"""

import hashlib;
import from core.catalog.storefront_api { public_seat_availability }
import from core.booking.hold_api { hold_seats, my_hold }
import from core.booking.order_api {
    quote_hold,
    place_order,
    my_order,
    public_ticket_types
}
import from core.payments.payment_api { start_payment }
import from core.payments.settlement { my_payment }
import from core.booking.customer_tickets { save_for_caller }
import from core.tenancy.principal { node_id, act_as, restore }
import from core.oauth.provider { base_url }

glob CARD_TOOL_NAMES: list[str] = [
         "card_state",
         "card_hold",
         "card_quote",
         "card_order",
         "card_pay",
         "card_status"
     ],
     SEATS_MAX: int = 10;

def holder_for(customer: str) -> str {
    # The customer's holder id for bookings from Claude: theirs alone, made here.
    return "claude-" + hashlib.sha256(customer.encode("utf-8")).hexdigest()[:40];
}

def _refusal(got: any, fallback: str) -> dict[str, any] {  # jac:ignore[W1037]
    if isinstance(got, dict) and isinstance(got.get("error"), dict) {
        return {
            "ok": False,
            "code": str(got["error"].get("code", "refused")),
            "message": str(got["error"].get("message", fallback))
        };
    }
    return {"ok": False, "code": "refused", "message": fallback};
}

def _ok(got: any) -> bool {  # jac:ignore[W1037]
    return isinstance(got, dict) and got.get("ok", False) == True;
}

def _payment(view: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    # What the card shows of a payment: never the phone number, only a masked email.
    return {
        "state": view.get("state", ""),
        "reference": view.get("reference", ""),
        "message": view.get("message", ""),
        "amount_cents": view.get("amount_cents", 0),
        "currency": view.get("currency", "")
    };
}

def _items(raw: any) -> list[dict[str, str]] {  # jac:ignore[W1037]
    return [
        {
            "seat_label": str(i.get("seat_label", "")),
            "ticket_type": str(i.get("ticket_type", ""))
        }
        for i in (raw if isinstance(raw, list) else [])[:SEATS_MAX]
        if isinstance(i, dict)
    ];
}

def _state(cinema: str, showtime: str, holder: str) -> dict[str, any] {  # jac:ignore[W1037]
    seats = public_seat_availability(cinema, showtime);
    if not _ok(seats) {
        return _refusal(seats, "This showtime isn't on sale.");
    }
    types = public_ticket_types(cinema);
    held = my_hold(cinema, showtime, holder);
    hold = held["hold"] if _ok(held) else None;
    mine: list[str] = hold["seats"] if hold is not None else [];
    ordered = my_order(cinema, showtime, holder);
    order = None;
    if _ok(ordered) {
        o = ordered["order"];
        order = {
            "total_cents": o.get("total_cents", 0),
            "currency": o.get("currency", ""),
            "seats": [str(l.get("seat_label", "")) for l in o.get("lines", [])]
        };
    }
    paying = my_payment(cinema, showtime, holder) if order is not None else None;
    return {
        "ok": True,
        "rows": seats["rows"],
        "cols": seats["cols"],
        "seats": [
            {
                "label": s["label"],
                "row": s["row"],
                "col": s["col"],
                "state": s["state"],
                "mine": s["label"] in mine
            } for s in seats["seats"]
        ],
        "ticket_types": types.get("ticket_types", []) if _ok(types) else [],
        "currency": types.get("currency", "") if _ok(types) else "",
        "hold": hold,
        "order": order,
        "payment": _payment(paying["payment"]) if _ok(paying) else None
    };
}

def _status(cinema: str, showtime: str, holder: str, customer: str) -> dict[str, any] {  # jac:ignore[W1037]
    got = my_payment(cinema, showtime, holder);
    if not _ok(got) {
        return _refusal(got, "There's no payment for this booking yet.");
    }
    view = got["payment"];
    answer = {
        "ok": True,
        ** _payment(view),
        "seats": [],
        "email": "",
        "tickets_url": ""
    };
    if view.get("state") != "success" {
        return answer;
    }
    link = str(view.get("link", ""));
    # Saved to the customer, as them: their bookings list it, and My tickets shows it.
    me = node_id(root);
    act_as(customer);
    try {
        save_for_caller(cinema, link.rsplit("/", 1)[-1]);
    } finally {
        restore(me);
    }
    return {
        ** answer,
        "seats": [str(t.get("seat_label", "")) for t in view.get("tickets", [])],
        "email": str(view.get("email", "")),
        "tickets_url": f"{base_url()}{link}" if link else ""
    };
}

def card_call(name: str, args: dict[str, any], customer: str) -> dict[str, any] {  # jac:ignore[W1037]
    # One card tool's answer, for the card only.
    if not customer {
        return {
            "ok": False,
            "code": "sign_in",
            "message": "Sign in to AfriCinemas in Claude to book here, or book on the cinema's website."
        };
    }
    cinema = str(args.get("cinema", ""));
    showtime = str(args.get("showtime_id", ""));
    holder = holder_for(customer);
    if name == "card_state" {
        return _state(cinema, showtime, holder);
    }
    if name == "card_hold" {
        labels = [
            str(x)
            for x in args.get("seats", [])
            if isinstance(x, str)
        ][:SEATS_MAX];
        got = hold_seats(cinema, showtime, holder, labels);
        return {"ok": True, "hold": got["hold"]}
            if _ok(got)
            else _refusal(got, "Those seats couldn't be held.");
    }
    if name == "card_quote" {
        got = quote_hold(cinema, showtime, holder, _items(args.get("items")));
        if not _ok(got) {
            return _refusal(got, "Those tickets couldn't be priced.");
        }
        return {
            "ok": True,
            "total": got["quote"]["total_cents"],
            "currency": got["quote"]["currency"]
        };
    }
    if name == "card_order" {
        got = place_order(
            cinema,
            showtime,
            holder,
            str(args.get("key", "")),
            _items(args.get("items"))
        );
        if not _ok(got) {
            return _refusal(got, "The order couldn't be placed.");
        }
        return {
            "ok": True,
            "total": got["order"].get("total_cents", 0),
            "currency": got["order"].get("currency", "")
        };
    }
    if name == "card_pay" {
        got = start_payment(
            cinema,
            showtime,
            holder,
            str(args.get("phone", "")),
            str(args.get("email", "")),
            str(args.get("key", ""))
        );
        if not _ok(got) {
            return _refusal(got, "The M-Pesa prompt couldn't be sent.");
        }
        return {"ok": True, ** _payment(got["payment"])};
    }
    if name == "card_status" {
        return _status(cinema, showtime, holder, customer);
    }
    return {
        "ok": False,
        "code": "unknown",
        "message": "The card asked for something unknown."
    };
}
