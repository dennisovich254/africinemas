"""The ticket email (P6.3, ADR-0010, ADR-0022): what a customer receives once paid.

From the cinema's name on our address, Reply-To the cinema's contact email when it has
one. It says what was booked (the movie, the showtime in the cinema's local time, the
venue and screen, the order reference), shows one QR code per seat as an image inside
the email (cid:, so it shows without loading anything), with the ticket reference under
it for typing in at the door, and links to the tickets page. An order with snacks lists
them with their pickup code (P12.9): its QR for the snack counter, and its reference.
Plain text and HTML say the same. Everything the cinema typed is escaped.
"""

import io;
import html;
import segno;
import from datetime { datetime }
import from zoneinfo { ZoneInfo }
import from email.utils { formataddr }
import from core.notify.mailer { OutgoingMail, MailImage }

glob QR_SCALE: int = 8,
     QR_SIZE_PX: int = 200,
     FOOTER: str = "Tickets by AfriCinemas";

obj MailTicket {
    has seat_label: str,
        ticket_name: str,
        reference: str,
        qr: str;
}

obj TicketMail {
    # What the ticket email says. starts_at is UTC ISO 8601; timezone the cinema's.
    has to: str,
        cinema_name: str,
        reply_to: str,
        movie_title: str,
        starts_at: str,
        timezone: str,
        place: str,
        order_reference: str,
        link: str,
        tickets: list[MailTicket] = [],
        # "2 × Popcorn · Large (Butter)" lines, and their pickup code (P12.9).
        snacks: list[str] = [],
        pickup_reference: str = "",
        pickup_qr: str = "";
}

def _when(starts_at: str, timezone: str) -> str {
    # "Friday 9 October 2026, 18:15" in the cinema's time zone.
    local = datetime.fromisoformat(starts_at).astimezone(ZoneInfo(timezone));
    # strftime, not an f-string format spec: Jac drops a spec's spaces (JI-040).
    return f"{local.strftime('%A')} {local.day} {local.strftime('%B %Y, %H:%M')}";
}

def _qr_png(payload: str) -> bytes {
    buffer = io.BytesIO();
    # segno has no type hints.
    code: any = segno.make_qr(payload, error="m");  # jac:ignore[W1037]
    code.save(buffer, kind="png", scale=QR_SCALE, border=4);
    return buffer.getvalue();
}

def ticket_mail(data: TicketMail, from_addr: str) -> OutgoingMail {
    when = _when(data.starts_at, data.timezone);
    e = html.escape;
    images: list[MailImage] = [];
    text_seats: list[str] = [];
    html_seats: list[str] = [];
    for (i, t) in enumerate(data.tickets) {
        cid = f"qr{i + 1}.{data.order_reference.lower()}@africinemas";
        images.append(
            MailImage(
                filename=f"ticket-{t.seat_label}.png",
                content=_qr_png(t.qr),
                content_id=cid
            )
        );
        text_seats.append(f"- Seat {t.seat_label} · {t.ticket_name}: {t.reference}");
        html_seats.append(
            '<tr><td style="padding:16px 0;border-top:1px solid #e5e5e5;text-align:center">'
                + f'<p style="margin:0 0 8px;font-weight:600">Seat {e(t.seat_label)} · {e(
                    t.ticket_name
                )}</p>'
                + f'<img src="cid:{cid}" width="{QR_SIZE_PX}" height="{QR_SIZE_PX}" '
                + f'alt="QR code for seat {e(
                    t.seat_label
                )}" style="display:block;margin:0 auto">'
                + f'<p style="margin:8px 0 0;font-family:monospace;font-size:16px;letter-spacing:1px">{e(
                    t.reference
                )}</p>'
                + "</td></tr>"
        );
    }
    text_snacks: list[str] = [];
    html_snacks = "";
    if data.snacks {
        text_snacks = ["", "Your snacks:"] + [f"- {s}" for s in data.snacks];
        html_snacks = (
            '<h2 style="font-size:16px;margin:24px 0 8px">Your snacks</h2><ul style="margin:0;padding-left:20px">'
            + "".join([f"<li>{e(s)}</li>" for s in data.snacks])
            + "</ul>"
        );
        if data.pickup_qr {
            cid = f"pickup.{data.order_reference.lower()}@africinemas";
            images.append(
                MailImage(
                    filename="snack-pickup.png",
                    content=_qr_png(data.pickup_qr),
                    content_id=cid
                )
            );
            text_snacks = text_snacks
                + [
                    f"Pickup code: {data.pickup_reference}. Show it at the snack counter, from two hours before the showtime."
                ];
            html_snacks = html_snacks
                + '<p style="margin:12px 0 8px">Show this code at the snack counter, from two hours before the showtime.</p>'
                + f'<img src="cid:{cid}" width="{QR_SIZE_PX}" height="{QR_SIZE_PX}" '
                + 'alt="Snack pickup code" style="display:block;margin:0 auto">'
                + f'<p style="margin:8px 0 0;text-align:center;font-family:monospace;font-size:16px;letter-spacing:1px">{e(
                    data.pickup_reference
                )}</p>';
        }
    }
    text = "\n".join(
        [
            f"Your tickets for {data.movie_title}",
            "",
            when,
            data.place,
            f"Order {data.order_reference}",
            "",
            "Show each ticket's QR code at the door (it's in this email's HTML version and on the tickets page). If a code won't scan, give the reference instead.",
            ""
        ]
            + text_seats
            + text_snacks
            + [
                "",
                f"Your tickets, any time: {data.link}",
                "",
                f"{data.cinema_name}",
                FOOTER
            ]
    );
    body = (
        '<div style="font-family:Arial,sans-serif;color:#111;max-width:480px;margin:0 auto">'
        + f'<h1 style="font-size:20px;margin:0 0 4px">Your tickets for {e(
            data.movie_title
        )}</h1>'
        + f'<p style="margin:0">{e(when)}</p>'
        + f'<p style="margin:0">{e(data.place)}</p>'
        + f'<p style="margin:0 0 16px;color:#555">Order {e(data.order_reference)}</p>'
        + '<p style="margin:0 0 8px">Show each ticket\'s QR code at the door. If a code won\'t scan, give the reference under it.</p>'
        + '<table role="presentation" width="100%" cellpadding="0" cellspacing="0">'
        + "".join(html_seats)
        + "</table>"
        + html_snacks
        + f'<p style="margin:16px 0"><a href="{e(
            data.link
        )}">Open your tickets</a> any time: {e(data.link)}</p>'
        + f'<p style="margin:24px 0 0;color:#555;font-size:13px">{e(
            data.cinema_name
        )} · {FOOTER}</p>'
        + "</div>"
    );
    return OutgoingMail(
        to=data.to,
        sender=formataddr((data.cinema_name, from_addr)),
        reply_to=data.reply_to,
        subject=f"Your tickets for {data.movie_title} at {data.cinema_name}",
        text=text,
        html=body,
        images=images
    );
}
