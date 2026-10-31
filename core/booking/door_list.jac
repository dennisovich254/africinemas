"""The door list (P17.2, docs/failure-modes.md 1.7): every paid ticket of a showtime, to
let people in on paper when the scanner can't reach AfriCinemas.

Staff who may scan or sell at the showtime's venue get it from noon, cinema time, the
day before (OPENS_HOUR): on screen, as a PDF to print (A4) or keep on a phone, and a
day's showtimes in one PDF. Each ticket: its seat, reference and type, the last three
digits of the booker's phone, and how it was paid (the M-Pesa code, which is on the
customer's M-Pesa message too, or cash). Tickets already scanned say so. Then the snacks
to collect, by pickup code, and lines to write down people who paid during an outage
and aren't on the list. Nothing else about the booker: no name, email or full phone.

Voided and refunded tickets, cancelled showtimes and unpaid orders aren't on it.
"""

import base64;
import from datetime { datetime, timedelta, date }
import from zoneinfo { ZoneInfo }
import from core.clock { now }
import from core.authz.policy { Resource, Forbidden, ROLE_PERMISSIONS, authorize }
import from core.authz.context { NotFound, TenantScope, on_shift }
import from core.tenancy.models { Tenant }
import from core.tenancy.principal { node_id, act_as, restore }
import from core.catalog.answers { Refused, answer }
import from core.audit.log { audited }
import from core.catalog.models { Screening }
import from core.catalog.venues {
    find_screening,
    find_movie,
    find_venue,
    find_auditorium,
    screenings_of_cinema
}
import from core.catalog.storefront_api { cinema_timezone }
import from core.booking.models { Order, Ticket }
import from core.booking.snack_additions { snack_batches, snack_lines_of }
import from core.payments.models { PaymentIntent }
import from core.billing.pdf { PdfLine, pdf_bytes }

glob SCAN: str = "tickets.scan",
     SELL: str = "bookings.create",
     # The list opens at this hour, cinema time, the day before the showtime.
     OPENS_HOUR: int = 12,
     NOT_SHOWN: list[str] = ["draft", "scheduled", "cancelled"],
     ON_THE_LIST: list[str] = ["issued", "used"],
     # Lines left for people who paid during an outage and aren't on the list.
     BLANK_LINES: int = 8;

def opens_at(screening: Screening, timezone: str) -> datetime {
    # Noon, cinema time, the day before the showtime.
    zone = ZoneInfo(timezone);
    day = datetime.fromisoformat(screening.starts_at).astimezone(zone).date();
    before = day - timedelta(days=1);
    return datetime(before.year, before.month, before.day, OPENS_HOUR, tzinfo=zone);
}

def _may(scope: TenantScope, venue_id: str) -> bool {
    # Who may scan or sell at the venue.
    where = Resource(tenant_id=scope.ctx.tenant_id, venue_id=venue_id);
    return authorize(scope.ctx, SCAN, where) or authorize(scope.ctx, SELL, where);
}

def _scope(tenant: str) -> TenantScope {
    scope = on_shift(tenant);
    roles = [ROLE_PERMISSIONS[a.role] for a in scope.ctx.assignments];
    if not any([SCAN in r or SELL in r for r in roles]) {
        raise Forbidden(SCAN);
    }
    return scope;
}

def _phone_end(phone: str) -> str {
    digits = "".join(
        [
            c
            for c in phone
            if c.isdigit()
        ]
    );
    return digits[-3:] if len(digits) >= 3 else "";
}

def _paid(order: Order) -> dict[str, str] {
    # How the order was paid: its successful M-Pesa payment, or cash at the counter.
    # Call as the cinema's principal.
    for p in [order-->[?:PaymentIntent]] {
        if p.state == "success" {
            return {
                "paid_with": "M-Pesa",
                "code": p.receipt,
                "phone_end": _phone_end(p.phone)
            };
        }
    }
    return {"paid_with": "Cash", "code": "", "phone_end": ""};
}

def _snack_text(lines: list[dict[str, any]]) -> str {  # jac:ignore[W1037]
    return ", ".join([f"{int(l['quantity'])} × {l['name']}" for l in lines]);
}

def _contents(cinema: Tenant, screening: Screening) -> dict[str, list[dict[str, any]]] {  # jac:ignore[W1037]
    # The showtime's tickets (by seat) and snacks (by pickup code), as the principal.
    tickets: list[dict[str, any]] = [];  # jac:ignore[W1037]
    snacks: list[dict[str, any]] = [];  # jac:ignore[W1037]
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        for order in [screening-->[?:Order]] {
            if order.status != "confirmed" or order.booking_id {
                continue;
            }
            paid = _paid(order);
            for t in [order-->[?:Ticket]] {
                if t.status not in ON_THE_LIST {
                    continue;
                }
                tickets.append(
                    {
                        "seat": t.seat_label,
                        "reference": t.reference,
                        "ticket_type": t.ticket_name,
                        "format": t.format,
                        "glasses": t.glasses_bought,
                        "used_at": t.used_at if t.status == "used" else "",
                        ** paid
                    }
                );
            }
            batches = snack_batches(cinema, order);
            lines = snack_lines_of(batches);
            if lines and order.pickup_reference {
                snacks.append(
                    {
                        "pickup": order.pickup_reference,
                        "items": _snack_text(lines),
                        "collected": all([bool(b.snacks_collected_at) for b in batches])
                    }
                );
            }
        }
    } finally {
        restore(me);
    }
    return {
        "tickets": sorted(
            tickets,
            key=lambda (t: dict[str, any]) -> str { return _seat_key(t["seat"]); }  # jac:ignore[W1037]
        ),
        "snacks": sorted(
            snacks,
            key=lambda (s: dict[str, any]) -> str { return s["pickup"]; }  # jac:ignore[W1037]
        )
    };
}

def _seat_key(label: str) -> str {
    # "B10" after "B9": the row's letters, then the number padded.
    letters = "".join(
        [
            c
            for c in label
            if not c.isdigit()
        ]
    );
    digits = "".join(
        [
            c
            for c in label
            if c.isdigit()
        ]
    );
    return f"{letters}{digits.zfill(4)}";
}

def _showtime(
    scope: TenantScope, screening: Screening, timezone: str
) -> dict[str, str] {
    movie = find_movie(scope.tenant, screening.movie_id);
    venue = find_venue(scope.tenant, screening.venue_id);
    screen = find_auditorium(scope.tenant, screening.auditorium_id);
    return {
        "screening_id": node_id(screening),
        "movie_title": movie.title if movie is not None else "",
        "starts_at": screening.starts_at,
        "venue": venue.name if venue is not None else "",
        "screen": screen.name if screen is not None else "",
        "opens_at": opens_at(screening, timezone).isoformat()
    };
}

def _open_list(tenant: str, screening_id: str) -> tuple[TenantScope, Screening, str] {
    # The caller's scope, the showtime and the cinema's timezone, once the caller may
    # have its door list now.
    scope = _scope(tenant);
    screening = find_screening(scope.tenant, screening_id);
    if screening is None or screening.state in NOT_SHOWN {
        raise NotFound();
    }
    if not _may(scope, screening.venue_id) {
        raise Forbidden(SCAN);
    }
    timezone = cinema_timezone(scope.tenant);
    opens = opens_at(screening, timezone);
    if now() < opens {
        raise Refused(
            "not_yet",
            f"This door list is ready from {opens.strftime('%A %-d %B at %H:%M')}.",
            {"opens_at": opens.isoformat()}
        );
    }
    return (scope, screening, timezone);
}

def _door_list(tenant: str, screening_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    (scope, screening, timezone) = _open_list(tenant, screening_id);
    return {
        "ok": True,
        "cinema": scope.tenant.name,
        "timezone": timezone,
        "showtime": _showtime(scope, screening, timezone),
        ** _contents(scope.tenant, screening)
    };
}

def _day_showtimes(scope: TenantScope, day: str, timezone: str) -> list[Screening] {
    # The day's showtimes (cinema time) at venues where the caller may scan or sell.
    zone = ZoneInfo(timezone);
    found = [
        s
        for s in screenings_of_cinema(scope.tenant)
        if s.state not in NOT_SHOWN
            and datetime.fromisoformat(s.starts_at).astimezone(zone).date().isoformat()
                == day
            and _may(scope, s.venue_id)
    ];
    return sorted(found, key=lambda (s: Screening) -> str { return s.starts_at; });
}

def _check_day(day: str) -> str {
    try {
        return date.fromisoformat(day).isoformat();
    } except ValueError {
        raise Refused("invalid_day", "Choose a day.");
    }
}

def _door_lists(tenant: str, day: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The day's showtimes, each saying when its list opens and how many tickets it has.
    scope = _scope(tenant);
    timezone = cinema_timezone(scope.tenant);
    at = now();
    shown: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for s in _day_showtimes(scope, _check_day(day), timezone) {
        row: dict[str, any] = _showtime(scope, s, timezone);  # jac:ignore[W1037]
        ready = at >= opens_at(s, timezone);
        row["ready"] = ready;
        row["tickets"] = len(_contents(scope.tenant, s)["tickets"]) if ready else 0;
        shown.append(row);
    }
    return {"ok": True, "timezone": timezone, "day": day, "showtimes": shown};
}

def _when(stamp: str, timezone: str, fmt: str) -> str {
    return datetime.fromisoformat(stamp).astimezone(ZoneInfo(timezone)).strftime(fmt);
}

def _pdf_lines(listing: dict[str, any], first: bool) -> list[PdfLine] {  # jac:ignore[W1037]
    # One showtime's pages.
    show = listing["showtime"];
    tz = listing["timezone"];
    tickets: list[dict[str, any]] = listing["tickets"];  # jac:ignore[W1037]
    snacks: list[dict[str, any]] = listing["snacks"];  # jac:ignore[W1037]
    where = ", ".join(
        [
            x
            for x in [show["screen"], show["venue"]]
            if x
        ]
    );
    lines: list[PdfLine] = [
        PdfLine(
            text=f"{listing['cinema']}: door list",
            size=16,
            bold=True,
            new_page=not first
        ),
        PdfLine(text=show["movie_title"], size=13, bold=True, gap=4),
        PdfLine(text=f"{_when(show['starts_at'], tz, '%A %-d %B, %H:%M')} · {where}"),
        PdfLine(
            text=f"{len(tickets)} {'ticket' if len(tickets) == 1 else 'tickets'}. Made {_when(
                now().isoformat(),
                tz,
                '%-d %B at %H:%M'
            )}: tickets sold after that aren't on it.",
            size=9
        ),
        PdfLine(text="Only if the scanner isn't working.", size=9, bold=True, gap=6),
        PdfLine(
            text="Tick each ticket as its person comes in. They show their ticket email (the reference) or",
            size=9
        ),
        PdfLine(
            text="their M-Pesa message (the code). A ticket already ticked can't come in again.",
            size=9
        ),
        PdfLine(
            text="Paid but not on the list? Check the M-Pesa message is to your cinema, for this showtime's",
            size=9
        ),
        PdfLine(
            text="price, sent before the showtime. Write it at the end; AfriCinemas matches it to the booking.",
            size=9
        ),
        PdfLine(
            text="Afterwards, mark the ticked tickets as used in the back office.",
            size=9
        )
    ];
    cols = [50.0, 80.0, 120.0, 215.0, 330.0, 380.0, 495.0];
    lines.append(
        PdfLine(
            bold=True,
            gap=8,
            cols=list(
                zip(
                    [
                        "",
                        "Seat",
                        "Ticket",
                        "Type",
                        "Phone",
                        "M-Pesa code / cash",
                        "Scanned"
                    ],
                    cols
                )
            )
        )
    );
    for t in tickets {
        kind = t["ticket_type"] + (f" {t['format']}" if t["format"] != "2D" else "");
        if t["glasses"] {
            kind += " + glasses";
        }
        paid = t["code"] if t["paid_with"] == "M-Pesa" else "Cash";
        lines.append(
            PdfLine(
                cols=list(
                    zip(
                        [
                            "[   ]",
                            t["seat"],
                            t["reference"],
                            kind[:22],
                            f"...{t['phone_end']}" if t["phone_end"] else "",
                            paid,
                            _when(t["used_at"], tz, "%H:%M") if t["used_at"] else ""
                        ],
                        cols
                    )
                )
            )
        );
    }
    if not tickets {
        lines.append(PdfLine(text="No tickets sold yet."));
    }
    if snacks {
        lines.append(PdfLine(text="Snacks to collect", bold=True, size=12, gap=10));
        lines.append(
            PdfLine(
                bold=True,
                cols=[
                    ("", 50.0),
                    ("Pickup code", 80.0),
                    ("Snacks", 160.0),
                    ("Collected", 480.0)
                ]
            )
        );
        for s in snacks {
            lines.append(
                PdfLine(
                    cols=[
                        ("[   ]", 50.0),
                        (s["pickup"], 80.0),
                        (s["items"][:60], 160.0),
                        ("Yes" if s["collected"] else "", 480.0)
                    ]
                )
            );
        }
    }
    lines.append(
        PdfLine(
            text="Paid during an outage, not on this list", bold=True, size=12, gap=10
        )
    );
    lines.append(
        PdfLine(
            bold=True,
            cols=[
                ("M-Pesa code", 50.0),
                ("Amount", 170.0),
                ("Seat", 260.0),
                ("Phone (last 3)", 330.0),
                ("Time paid", 440.0)
            ]
        )
    );
    for _ in range(BLANK_LINES) {
        lines.append(PdfLine(text="_" * 92, gap=6));
    }
    return lines;
}

def _pdf_answer(lines: list[PdfLine], title: str, filename: str) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "ok": True,
        "filename": filename,
        "pdf": base64.b64encode(pdf_bytes(lines, title)).decode("ascii")
    };
}

def _door_list_pdf(tenant: str, screening_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    listing = _door_list(tenant, screening_id);
    show = listing["showtime"];
    stamp = _when(show["starts_at"], listing["timezone"], "%Y-%m-%d-%H%M");
    return _pdf_answer(
        _pdf_lines(listing, True),
        f"Door list: {show['movie_title']}",
        f"door-list-{stamp}.pdf"
    );
}

def _day_door_lists_pdf(tenant: str, day: str) -> dict[str, any] {  # jac:ignore[W1037]
    # Every showtime of the day whose list is open, one after another.
    scope = _scope(tenant);
    timezone = cinema_timezone(scope.tenant);
    at = now();
    lines: list[PdfLine] = [];
    for s in _day_showtimes(scope, _check_day(day), timezone) {
        if at < opens_at(s, timezone) {
            continue;
        }
        listing = _door_list(tenant, node_id(s));
        lines.extend(_pdf_lines(listing, len(lines) == 0));
    }
    if not lines {
        raise Refused("nothing_yet", "No door lists are ready for this day.");
    }
    return _pdf_answer(lines, f"Door lists {day}", f"door-lists-{day}.pdf");
}

def:protect door_lists(tenant: str, day: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The day's showtimes, at venues where the caller may scan or sell, with their lists.
    return answer(lambda -> any { return _door_lists(tenant, day); });  # jac:ignore[W1037]
}

def:protect door_list(tenant: str, screening_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _door_list(tenant, screening_id); });  # jac:ignore[W1037]
}

def:protect door_list_pdf(tenant: str, screening_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    # Downloads are audited: the list leaves AfriCinemas, on paper or a phone.
    return audited(
        tenant,
        "door_list.downloaded",
        "showtime",
        screening_id,
        lambda -> any { return answer(
            lambda -> any { return _door_list_pdf(tenant, screening_id); }
        ); }  # jac:ignore[W1037]
    );
}

def:protect day_door_lists_pdf(tenant: str, day: str) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "door_list.downloaded",
        "day",
        day,
        lambda -> any { return answer(
            lambda -> any { return _day_door_lists_pdf(tenant, day); }
        ); }  # jac:ignore[W1037]
    );
}
