"""`/c/:slug/my-tickets`: a signed-in customer's saved bookings at this cinema (P6.3b).

Upcoming showtimes first (soonest first), then past ones (latest first). Each says what
and when, where, and which seats, and opens its tickets page. Tickets are saved here
when a signed-in visitor sees them (TicketDelivery.SaveToAccount). A visitor who isn't
signed in with this cinema's customer account (P8.6c) is asked to sign in or create
one here, and comes back to this page.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { useParams, jacIsLoggedIn }
import from core.booking.customer_tickets { my_tickets }  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)
import from .StorefrontShell { StorefrontShell, Loading }
import from .venue_choice { use_title }
import from .showtimes { long_day_label, time_label }
import from ..shell.AppLink { AppLink }

def BookingRow(booking: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
    tz: str = booking["timezone"];
    starts_at: str = booking["starts_at"];
    tickets: list[dict[str, str]] = booking["tickets"];
    seats: str = ", ".join([t["seat_label"] for t in tickets]);
    place: str = " · ".join(
        [
            p
            for p in [booking["venue"], booking["screen"]]
            if p
        ]
    );
    count: int = len(tickets);
    return
        <li
            data-testid="saved-booking"
            className="flex flex-col gap-3 rounded-lg border bg-card p-4 sm:flex-row sm:items-center sm:justify-between"
        >
            <div className="flex flex-col gap-0.5">
                <p className="text-lg font-semibold">{booking["movie_title"]}</p>
                <p className="font-medium">
                    {f"{long_day_label(starts_at, tz)}, {time_label(starts_at, tz)}"}
                </p>
                <p className="text-sm text-muted-foreground">{place}</p>
                <p className="text-sm text-muted-foreground">
                    {f"{count} {'ticket' if count == 1 else 'tickets'} · Seats {seats}"}
                </p>
            </div>
            <AppLink
                to={booking["link"]}
                testid="open-saved-booking"
                className="inline-flex min-h-11 w-fit items-center rounded-md border px-4 text-sm font-medium hover:bg-muted"
            >
                Open tickets
            </AppLink>
        </li>;
}

def:pub MyTicketsPage -> JsxElement {
    params: any = useParams();  # jac:ignore[W1037,W1051]
    slug: str = params["slug"] or "";
    signed_in: bool = jacIsLoggedIn();
    [page, set_page] = useState(None);

    async def load {
        shown: any = None;  # jac:ignore[W1037]
        try {
            shown = await my_tickets(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("my tickets load failed", e);
            shown = {"ok": False};
        }
        set_page(shown);
    }

    def start_loading -> any {  # jac:ignore[W1037]
        if signed_in {
            load();
        }
        return lambda {};
    }
    useEffect(start_loading, [slug, signed_in]);

    use_title("My tickets");
    found: dict[str, any] | None = page;  # jac:ignore[W1037]
    if not signed_in or (found is not None and not found["ok"]) {
        # Signed in, but refused: the account is staff's or another cinema's customer's.
        other: bool = signed_in
            and found is not None
            and found["error"]["code"] == "not_your_cinema";
        back: str = f"?next=/c/{slug}/my-tickets";
        return
            <StorefrontShell slug={slug}>
                <section
                    data-testid="my-tickets-signed-out"
                    className="flex flex-col items-start gap-3 rounded-lg border bg-card p-6"
                >
                    <h1 className="font-display text-4xl leading-none">My tickets</h1>
                    <p className="text-muted-foreground">
                        {"You're signed in with an account that isn't for this cinema. Sign in with your account here to see your tickets."
                            if other
                            else "Sign in to see the tickets saved to your account. Tickets you bought as a guest are in your ticket email."}
                    </p>
                    <div className="flex flex-wrap gap-3">
                        <AppLink
                            to={f"/c/{slug}/sign-in{back}"}
                            testid="sign-in-for-tickets"
                            className="inline-flex min-h-11 items-center rounded-md bg-primary px-4 font-medium text-primary-foreground"
                        >
                            Sign in
                        </AppLink>
                        <AppLink
                            to={f"/c/{slug}/sign-up{back}"}
                            testid="sign-up-for-tickets"
                            className="inline-flex min-h-11 items-center rounded-md border px-4 font-medium hover:bg-muted"
                        >
                            Create an account
                        </AppLink>
                    </div>
                </section>
            </StorefrontShell>;
    }
    if found is None {
        return
            <StorefrontShell slug={slug}>
                <Loading/>
            </StorefrontShell>;
    }
    bookings: list[dict[str, any]] = found["bookings"];  # jac:ignore[W1037]
    upcoming = [
        b
        for b in bookings
        if b["upcoming"]
    ];
    past = [
        b
        for b in bookings
        if not b["upcoming"]
    ];
    return
        <StorefrontShell slug={slug}>
            <section data-testid="my-tickets" className="flex flex-col gap-6">
                <h1 className="font-display text-4xl leading-none">My tickets</h1>
                {len(bookings) == 0
                    and <p
                        data-testid="no-saved-tickets"
                        className="text-muted-foreground"
                    >
                        No saved tickets yet. Tickets you buy while signed in appear here.
                    </p>}
                {len(upcoming) > 0
                    and <div className="flex flex-col gap-3">
                        <h2 className="text-lg font-semibold">Upcoming</h2>
                        <ul className="flex flex-col gap-3">
                            {[
                                <BookingRow key={b["link"]} booking={b}/>
                                for b in upcoming
                            ]}
                        </ul>
                    </div>}
                {len(past) > 0
                    and <div className="flex flex-col gap-3">
                        <h2 className="text-lg font-semibold">Past</h2>
                        <ul className="flex flex-col gap-3">
                            {[<BookingRow key={b["link"]} booking={b}/> for b in past]}
                        </ul>
                    </div>}
            </section>
        </StorefrontShell>;
}
