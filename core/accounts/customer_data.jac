"""A customer's own data at a cinema: download it, or delete the account (P15.0).

So a cinema can answer access, portability and erasure requests in time
(docs/legal/data-requests-procedure.md), its customers do both themselves on My account.

- my_data(slug): everything held about the caller at this cinema, as JSON: the account,
  their bookings (those saved to it, and any made with its email), the offers record
  and the apps they connected. Works while a deletion is pending.
- request_account_deletion(slug, password): after the password, the account is locked
  (storefront_accounts.require_customer_of) and deleted DELETE_AFTER_DAYS later unless
  they cancel (owner, 2026-10-29). cancel_account_deletion(slug) keeps it.
- delete_due_accounts: every DELETE_SECONDS, deletes those whose time is up:
  - the sign-in, the customer profile and the list of saved bookings;
  - the apps they connected, disconnected;
  - the offers record, marked withdrawn (kept as proof that offers stopped);
  - the email on their orders whose showtime has passed (owner, 2026-10-29). The
    orders stay: they're the cinema's sales records, which tax law keeps, and the
    phone stays with the M-Pesa receipt as the payment record. Upcoming tickets keep
    working.
  What's kept, and why, is in KEPT (core/tenancy/storefront_accounts.jac), which the
  page shows.
"""

import os;
import json;
import from datetime { datetime, timedelta }
import from jaclang { JacRuntime as Jac }
import from core.clock { now }
import from core.claims { claim, holder, release, claims_in, take_claim }
import from core.catalog.answers { Refused, answer }
import from core.tenancy.models { Tenant, CustomerProfile }
import from core.tenancy.principal { node_id, same_id, act_as, restore, flush_now }
import from core.tenancy.storefront_accounts {
    ACCOUNTS,
    DELETING,
    KEPT,
    account_of,
    deletion_of,
    require_customer_of,
    sign_in_name,
    old_sign_in_name
}
import from core.tenancy.customer_api { PROFILE_CLAIMS }
import from core.catalog.models { Auditorium, Screening, Venue }
import from core.booking.models { Order }
import from core.booking.customer_tickets { SAVED }
import from core.booking.ticket_delivery { booking_view }
import from core.payments.ledger { LedgerEntry }
import from core.notify.offer_consent { consent_of, record_consent }
import from core.oauth.state { connections_of, end_connection }
import from core.oauth.accounts { delete_chat_account }
import from core.platform.cinemas_api { all_cinemas }

glob DELETE_AFTER_DAYS: int = 7,
     DELETE_SECONDS: int = int(os.environ.get("AFRICINEMAS_DELETE_SECONDS", "3600")),
     # Erased accounts, for the record that a request was answered: no email or name.
     DELETED: str = "customer-deleted";

def _as_cinema(cinema: Tenant, work: any) -> any {  # jac:ignore[W1037]
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        return work();
    } finally {
        restore(me);
    }
}

def _orders(cinema: Tenant) -> list[tuple[Order, str]] {
    # Every order of the cinema, with its showtime's start ("" for snacks only).
    def walk -> any {  # jac:ignore[W1037]
        found: list[tuple[Order, str]] = [];
        for venue in [cinema-->[?:Venue]] {
            found.extend([(o, "") for o in [venue-->[?:Order]]]);
            for screen in [venue-->[?:Auditorium]] {
                for s in [screen-->[?:Screening]] {
                    found.extend([(o, s.starts_at) for o in [s-->[?:Order]]]);
                }
            }
        }
        return found;
    }
    return _as_cinema(cinema, walk);
}

def _theirs(cinema: Tenant, root_id: str, email: str) -> list[tuple[Order, str]] {
    # Their orders: saved to the account, or made with its email.
    saved = [key for (key, _, _) in claims_in(f"{SAVED}:{node_id(cinema)}:{root_id}")];
    return [
        (o, starts)
        for (o, starts) in _orders(cinema)
        if node_id(o) in saved or (email and o.email.strip().lower() == email)
    ];
}

def _booking(cinema: Tenant, order: Order) -> dict[str, any] {  # jac:ignore[W1037]
    view = booking_view(cinema, order);
    paid = _as_cinema(
        cinema,
        lambda -> any { return [
            {
                "kind": e.kind,
                "method": e.method,
                "amount_cents": e.amount_cents,
                "receipt": e.receipt,
                "at": e.created_at
            } for e in [order-->[?:LedgerEntry]]
        ]; }
    );
    return {
        "reference": order.reference,
        "status": order.status,
        "film": view["movie_title"],
        "rating": view["age_rating"],
        "starts_at": view["starts_at"],
        "venue": view["venue"],
        "screen": view["screen"],
        "email": order.email,
        "total_cents": order.total_cents,
        "tickets": [
            {
                "seat": t["seat_label"],
                "type": t["ticket_name"],
                "reference": t["reference"]
            } for t in view["tickets"]
        ],
        "snacks": [
            {"name": s["name"], "quantity": s["quantity"]} for s in view["snacks"]
        ],
        "payments": paid
    };
}

def _mine(slug: str) -> tuple[Tenant, str, dict[str, str]] {
    require_customer_of(slug, True);
    me = node_id(root);
    found = account_of(me) or {};
    cinemas = [
        c
        for c in all_cinemas()
        if c.slug == found.get("slug", "")
    ];
    if not cinemas {
        raise Refused("not_your_cinema", "Sign in with your account at this cinema.");
    }
    return (cinemas[0], me, found);
}

def _my_data(slug: str) -> dict[str, any] {  # jac:ignore[W1037]
    (cinema, me, found) = _mine(slug);
    email = found.get("email", "");
    return {
        "ok": True,
        "data": {
            "made_at": now().isoformat(),
            "cinema": cinema.name,
            "account": {"email": email, "name": found.get("name", "")},
            "bookings": [_booking(cinema, o) for (o, _) in _theirs(cinema, me, email)],
            "offers": consent_of(cinema, email),
            "connected_apps": [
                {"name": c["name"], "connected_at": c["connected_at"]}
                for (_, c) in connections_of(me)
                if c.get("slug") == cinema.slug
            ],
            "deleting": deletion_of(me),
            "kept_after_deletion": KEPT
        }
    };
}

def _users -> any {  # jac:ignore[W1037]
    return Jac.get_user_manager(Jac.get_context().base_path_dir or "");
}

def _request(slug: str, password: str) -> dict[str, any] {  # jac:ignore[W1037]
    (cinema, me, found) = _mine(slug);
    if deletion_of(me) is not None {
        return {"ok": True, "deleting": deletion_of(me), "kept": KEPT};
    }
    if not isinstance(password, str) or not password {
        raise Refused("wrong_password", "Enter your password.");
    }
    email = found.get("email", "");
    signed: any = None;  # jac:ignore[W1037]
    for name in [
        sign_in_name(cinema.slug, email),
        old_sign_in_name(cinema.slug, email)
    ] {
        if signed is None and _users().find_user_by_identity(name) {
            try {
                signed = _users().authenticate(name, password, "account");
            } except Exception {
                raise Refused(
                    "too_many_tries",
                    "Too many tries. Wait a few minutes, then try again."
                );
            }
        }
    }
    if not signed {
        raise Refused("wrong_password", "That isn't your password.");
    }
    at = now();
    record = {
        "slug": cinema.slug,
        "asked_at": at.isoformat(),
        "due": (at + timedelta(days=DELETE_AFTER_DAYS)).isoformat()
    };
    claim(DELETING, same_id(me), json.dumps(record, sort_keys=True));
    return {"ok": True, "deleting": record, "kept": KEPT};
}

def _cancel(slug: str) -> dict[str, any] {  # jac:ignore[W1037]
    (_, me, _) = _mine(slug);
    take_claim(DELETING, same_id(me));
    return {"ok": True, "deleting": None};
}

def erase(cinema: Tenant, root_id: str) {
    # Deletes the account `root_id` at `cinema`, as the module says.
    found = account_of(root_id) or {};
    email = found.get("email", "");
    at = now();
    # The email off their orders whose showtime has passed.
    def blank {
        for (o, starts) in _theirs(cinema, root_id, email) {
            if starts and datetime.fromisoformat(starts) < at {
                o.email = "";
            }
        }
        flush_now();
    }
    _as_cinema(cinema, blank);
    # Offers: withdrawn, the record kept.
    if email {
        record_consent(cinema, email, False, "account");
    }
    # Apps they connected.
    for (client_id, c) in connections_of(root_id) {
        if c.get("slug") == cinema.slug {
            ended = end_connection(root_id, client_id);
            if ended is not None {
                delete_chat_account(ended["user_id"]);
            }
        }
    }
    # The saved bookings list and the customer profile.
    saved = f"{SAVED}:{node_id(cinema)}:{root_id}";
    for (key, owner, _) in claims_in(saved) {
        release(saved, key, owner);
    }
    profile_key = f"{node_id(cinema)}:{root_id}";
    profile_id = holder(PROFILE_CLAIMS, profile_key);
    if profile_id {
        def drop {
            found_node: any = jobj(profile_id);  # jac:ignore[W1037]
            if found_node is not None and isinstance(found_node, CustomerProfile) {
                Jac.destroy([found_node]);
            }
            flush_now();
        }
        _as_cinema(cinema, drop);
        take_claim(PROFILE_CLAIMS, profile_key);
    }
    # The sign-in itself.
    for name in [
        sign_in_name(cinema.slug, email),
        old_sign_in_name(cinema.slug, email)
    ] {
        user: any = _users().find_user_by_identity(name) if email else None;  # jac:ignore[W1037]
        if user {
            _users().delete_user(str(user.get("user_id", "")));
        }
    }
    take_claim(ACCOUNTS, same_id(root_id));
    take_claim(DELETING, same_id(root_id));
    claim(
        DELETED,
        f"{node_id(cinema)}:{same_id(root_id)}",
        json.dumps({"slug": cinema.slug, "at": at.isoformat()})
    );
}

def delete_due(at: datetime) -> int {
    # Deletes every account whose time is up; how many.
    by_slug = {c.slug: c for c in all_cinemas()};
    done = 0;
    for (key, kept, _) in claims_in(DELETING) {
        record = json.loads(kept);
        cinema = by_slug.get(record.get("slug", ""));
        if cinema is not None and datetime.fromisoformat(record["due"]) <= at {
            erase(cinema, key);
            done += 1;
        }
    }
    return done;
}

def:protect my_data(slug: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _my_data(slug); });  # jac:ignore[W1037]
}

def:protect request_account_deletion(slug: str, password: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _request(slug, password); });  # jac:ignore[W1037]
}

def:protect cancel_account_deletion(slug: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _cancel(slug); });  # jac:ignore[W1037]
}

@schedule(trigger=ScheduleTrigger.STATIC, interval=DELETE_SECONDS)
def delete_due_accounts {
    # Runs as Jac's system identity on every server copy; each account is deleted once.
    done = delete_due(now());
    if done {
        print(f"customer data: {done} accounts deleted");
    }
}
