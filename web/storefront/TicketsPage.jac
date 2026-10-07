"""`/c/:slug/tickets/:token`: a paid order's tickets, for whoever holds the link (P6.3a).

The link is in the ticket email and on "You're booked". The page shows what was booked
(the movie, the day and time in the cinema's time zone, where, the order reference),
one QR card per seat, and the delivery controls: copy the link, resend the email, or
send it to a corrected address. A wrong or unknown link says so, without hinting
whether the booking exists.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { useParams }
import from core.booking.ticket_delivery { tickets_by_link }
import from .StorefrontShell { StorefrontShell, Loading }
import from .venue_choice { use_title }
import from .showtimes { long_day_label, time_label }
import from .PayPanel { TicketCard }
import from .TicketDelivery { TicketDelivery }
import from ..shell.AppLink { AppLink }

def:pub TicketsPage -> JsxElement {
    params: any = useParams();  # jac:ignore[W1037,W1051]
    slug: str = params["slug"] or "";
    token: str = params["token"] or "";
    [page, set_page] = useState(None);

    async def load {
        shown: any = None;  # jac:ignore[W1037]
        try {
            shown = await tickets_by_link(slug, token);
        } except Exception as e {
            console.warn("tickets load failed", e);
            shown = {"ok": False};
        }
        set_page(shown);
    }

    def start_loading {
        load();
    }
    useEffect(start_loading, [slug, token]);

    found: dict[str, any] | None = page;  # jac:ignore[W1037]
    booking: dict[str, any] | None = found["booking"]  # jac:ignore[W1037]
        if found is not None and found["ok"]
        else None;
    use_title(
        f"Your tickets: {booking['movie_title']}"
            if booking is not None
            else "Your tickets"
    );
    if found is None {
        return
            <StorefrontShell slug={slug}>
                <Loading/>
            </StorefrontShell>;
    }
    if booking is None {
        return
            <StorefrontShell slug={slug}>
                <div
                    data-testid="tickets-missing"
                    className="flex flex-col items-start gap-3 rounded-lg border bg-card p-6"
                >
                    <h1 className="font-display text-3xl leading-none">
                        Tickets not found
                    </h1>
                    <p className="text-muted-foreground">
                        This link doesn't open any tickets. Check that it's the whole link from your ticket email.
                    </p>
                    <AppLink
                        to={f"/c/{slug}"}
                        testid="back-to-cinema"
                        className="inline-flex min-h-11 items-center rounded-md bg-primary px-4 font-medium text-primary-foreground"
                    >
                        See what's on
                    </AppLink>
                </div>
            </StorefrontShell>;
    }
    tz: str = booking["timezone"];
    starts_at: str = booking["starts_at"];
    tickets: list[dict[str, str]] = booking["tickets"];
    place: str = " · ".join(
        [
            p
            for p in [booking["venue"], booking["screen"]]
            if p
        ]
    );
    return
        <StorefrontShell slug={slug}>
            <section
                data-testid="tickets-page"
                aria-labelledby="tickets-heading"
                className="flex flex-col gap-6"
            >
                <div className="flex flex-col gap-1">
                    <h1
                        id="tickets-heading"
                        className="font-display text-4xl leading-none"
                    >
                        {booking["movie_title"]}
                    </h1>
                    <p data-testid="tickets-when" className="text-lg font-medium">
                        {f"{long_day_label(starts_at, tz)}, {time_label(
                            starts_at, tz
                        )}"}
                    </p>
                    <p className="text-muted-foreground">{place}</p>
                    <p className="text-sm text-muted-foreground">
                        {f"Order {booking[
                            'reference'
                        ]} · Show each ticket's QR code at the door."}
                    </p>
                </div>
                <ul className="grid gap-3 sm:grid-cols-2">
                    {[<TicketCard key={t["reference"]} ticket={t}/> for t in tickets]}
                </ul>
                <TicketDelivery
                    link={f"/c/{slug}/tickets/{token}"}
                    email={booking["email"]}
                    show_open={False}
                />
            </section>
        </StorefrontShell>;
}
