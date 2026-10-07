"""Getting tickets to the customer (P6.3a, ADR-0010, ADR-0022): the private ticket link,
the ticket email and resending it.

- **The link** is /c/<slug>/tickets/<token>. The token is an HMAC over the order
  (ticket_codes.link_token), made again whenever it's needed and never stored; the
  claim LINKS maps its SHA-256 hash to the order ("<tenant id>|<order id>"). Settling
  a payment claims it provisionally and makes it permanent once the tickets are stored.
  Holding the link is enough to see the tickets and resend them, nothing more.
- **The email** is queued, never sent inside a request: MAIL_QUEUE holds one claim per
  email to send ("<tenant id>|<order id>|<address>"), and the send_ticket_mail job sends
  them every AFRICINEMAS_MAIL_SECONDS (default 5). A send that fails stays queued for the
  next run. SENDING keeps two servers from sending the same email at once.
- **Resending** (resend_tickets) queues the email again, to the order's address or a
  corrected one (which then becomes the order's), at most RESENDS_PER_HOUR times an
  hour per order: each resend takes one of that many hour-long claims.
- tickets_by_link and resend_tickets are public storefront endpoints. A wrong token, one
  for another cinema, or an order that isn't paid all answer not_found, alike.
"""

import os;
import math;
import from core.claims { claim, release, make_permanent, claims_in, holder }
import from core.tenancy.models { Tenant }
import from core.tenancy.open_cinema { open_cinema, tenant_by_id }
import from core.tenancy.principal {
    node_id,
    act_as,
    restore,
    commit_now,
    fresh_node_id
}
import from core.authz.context { NotFound }
import from core.catalog.answers { Refused, answer }
import from core.catalog.venues {
    find_screening,
    find_movie,
    find_venue,
    find_auditorium
}
import from core.catalog.storefront { home_of }
import from core.catalog.storefront_api { cinema_timezone }
import from core.booking.models { Order, Ticket }
import from core.booking.ticket_codes { link_token, link_key }
import from core.notify.addresses { email_problem, clean_email, masked_email }
import from core.notify.mailer { send, from_address }
import from core.notify.ticket_mail { TicketMail, MailTicket, ticket_mail }

glob LINKS: str = "order-link",
     MAIL_QUEUE: str = "ticket-mail",
     SENDING: str = "ticket-mail-sending",
     RESENDS: str = "ticket-resend",
     RESENDS_PER_HOUR: int = 3,
     HOUR_S: int = 3600,
     SENDING_S: int = 120,
     PUBLIC_URL_ENV: str = "AFRICINEMAS_PUBLIC_URL",
     DEFAULT_PUBLIC_URL: str = "http://localhost:8000",
     MAIL_SECONDS: int = int(os.environ.get("AFRICINEMAS_MAIL_SECONDS", "5"));

def link_path(cinema: Tenant, order: Order) -> str {
    return f"/c/{cinema.slug}/tickets/{link_token(node_id(cinema), node_id(order))}";
}

def _link_claim(cinema: Tenant, order: Order) -> tuple[str, str] {
    # (the claim's key, its owner) for the order's link.
    key = link_key(link_token(node_id(cinema), node_id(order)));
    return (key, f"{node_id(cinema)}|{node_id(order)}");
}

def claim_link(cinema: Tenant, order: Order, ttl_seconds: int) {
    # Makes the order's link findable, provisionally until keep_link.
    (key, owner) = _link_claim(cinema, order);
    claim(LINKS, key, owner, ttl_seconds);
}

def keep_link(cinema: Tenant, order: Order) {
    (key, owner) = _link_claim(cinema, order);
    make_permanent(LINKS, key, owner);
}

def queue_mail(cinema: Tenant, order: Order, address: str) {
    # Queues the order's ticket email to `address`; the job sends it.
    claim(MAIL_QUEUE, fresh_node_id(), f"{node_id(cinema)}|{node_id(order)}|{address}");
}

def _order(cinema: Tenant, order_id: str) -> Order | None {
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found: any = jobj(order_id);  # jac:ignore[W1037]
    } except Exception {
        found = None;
    } finally {
        restore(me);
    }
    return found as Order if isinstance(found, Order) else None;
}

def _tickets(cinema: Tenant, order: Order) -> list[Ticket] {
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = [t for t in [order-->[?:Ticket]]];
    } finally {
        restore(me);
    }
    return sorted(found, key=lambda (t: Ticket) -> str { return t.seat_label; });
}

def _place(cinema: Tenant, venue_id: str, auditorium_id: str) -> tuple[str, str] {
    venue = find_venue(cinema, venue_id);
    screen = find_auditorium(cinema, auditorium_id);
    return (
        venue.name if venue is not None else "",
        screen.name if screen is not None else ""
    );
}

def _contact_email(cinema: Tenant) -> str {
    # The cinema's contact email from its published home page, for Reply-To; "" if none.
    contact: any = home_of(cinema).get("contact") or {};  # jac:ignore[W1037]
    found = contact.get("email", "") if isinstance(contact, dict) else "";
    return found if isinstance(found, str) and not email_problem(found) else "";
}

def booking_view(cinema: Tenant, order: Order) -> dict[str, any] {  # jac:ignore[W1037]
    # What the tickets page shows.
    screening = find_screening(cinema, order.screening_id);
    movie = find_movie(cinema, screening.movie_id) if screening is not None else None;
    (venue, screen) = _place(cinema, screening.venue_id, screening.auditorium_id)
        if screening is not None
        else ("", "");
    return {
        "reference": order.reference,
        "movie_title": movie.title if movie is not None else "",
        "starts_at": screening.starts_at if screening is not None else "",
        "timezone": cinema_timezone(cinema),
        "venue": venue,
        "screen": screen,
        "email": masked_email(order.email) if order.email else "",
        "tickets": [
            {
                "seat_label": t.seat_label,
                "ticket_name": t.ticket_name,
                "reference": t.reference,
                "qr": t.qr,
                "status": t.status
            } for t in _tickets(cinema, order)
        ]
    };
}

def _mail_for(cinema: Tenant, order: Order, address: str) -> TicketMail {
    view = booking_view(cinema, order);
    base = os.environ.get(PUBLIC_URL_ENV, "").strip().rstrip("/") or DEFAULT_PUBLIC_URL;
    place = " · ".join(
        [
            p
            for p in [view["venue"], view["screen"]]
            if p
        ]
    );
    return TicketMail(
        to=address,
        cinema_name=cinema.name,
        reply_to=_contact_email(cinema),
        movie_title=view["movie_title"],
        starts_at=view["starts_at"],
        timezone=view["timezone"],
        place=place,
        order_reference=order.reference,
        link=f"{base}{link_path(cinema, order)}",
        tickets=[
            MailTicket(
                seat_label=t["seat_label"],
                ticket_name=t["ticket_name"],
                reference=t["reference"],
                qr=t["qr"]
            ) for t in view["tickets"]
        ]
    );
}

def send_due -> int {
    # Sends every queued ticket email; returns how many went.
    sent = 0;
    for (key, queued, _) in claims_in(MAIL_QUEUE) {
        mine = fresh_node_id();
        if claim(SENDING, key, mine, SENDING_S) != mine {
            continue;
        }
        try {
            (tenant_id, order_id, address) = queued.split("|", 2);
            cinema = tenant_by_id(tenant_id);
            order = _order(cinema, order_id) if cinema is not None else None;
            if cinema is None or order is None {
                release(MAIL_QUEUE, key, queued);
                continue;
            }
            if send(ticket_mail(_mail_for(cinema, order, address), from_address())) {
                release(MAIL_QUEUE, key, queued);
                sent += 1;
            }
        } finally {
            release(SENDING, key, mine);
        }
    }
    return sent;
}

@schedule(trigger=ScheduleTrigger.STATIC, interval=MAIL_SECONDS)
def send_ticket_mail {
    # Runs as Jac's system identity on every server copy; SENDING keeps one per email.
    send_due();
}

def _by_link(slug: str, token: str) -> tuple[Tenant, Order] {
    # The paid order a link names, at this cinema; NotFound otherwise.
    cinema = open_cinema(slug);
    owner = holder(LINKS, link_key(token.strip())) if cinema is not None else None;
    if cinema is None or owner is None {
        raise NotFound();
    }
    (tenant_id, _, order_id) = owner.partition("|");
    order = _order(cinema, order_id) if tenant_id == node_id(cinema) else None;
    if order is None or order.status != "confirmed" {
        raise NotFound();
    }
    return (cinema, order);
}

def _resend_slot(order: Order) -> int {
    # Takes one of the order's resends this hour; 0 if one was free, else the seconds
    # until the oldest frees up.
    space = f"{RESENDS}:{node_id(order)}";
    mine = fresh_node_id();
    for slot in range(RESENDS_PER_HOUR) {
        if claim(space, str(slot), mine, HOUR_S) == mine {
            return 0;
        }
    }
    ages = [
        age
        for (_, _, age) in claims_in(space)
        if age < HOUR_S
    ];
    return max(1, math.ceil(HOUR_S - max(ages))) if ages else 1;
}

def _resend(slug: str, token: str, email: str) -> dict[str, any] {  # jac:ignore[W1037]
    (cinema, order) = _by_link(slug, token);
    address = order.email;
    if email.strip() {
        if email_problem(email) {
            raise Refused("invalid_email", email_problem(email));
        }
        address = clean_email(email);
    }
    retry_after = _resend_slot(order);
    if retry_after > 0 {
        raise Refused(
            "too_many_resends",
            "Your tickets were sent several times in the last hour. Try again later.",
            {"retry_after_s": retry_after}
        );
    }
    if address != order.email {
        me = node_id(root);
        act_as(cinema.principal_root_id);
        try {
            order.email = address;
            commit_now();
        } finally {
            restore(me);
        }
    }
    queue_mail(cinema, order, address);
    return {"ok": True, "email": masked_email(address)};
}

def:pub tickets_by_link(slug: str, token: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(
        lambda -> any {  # jac:ignore[W1037]
            (cinema, order) = _by_link(slug, token);
            return {"ok": True, "booking": booking_view(cinema, order)};
        }
    );
}

def:pub resend_tickets(slug: str, token: str, email: str = "") -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _resend(slug, token, email); });  # jac:ignore[W1037]
}
