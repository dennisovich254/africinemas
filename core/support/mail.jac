"""Telling a cinema we've replied to its help request (P13.5b), by email.

A reply from AfriCinemas queues one email to each of the cinema's owners (REPLY_MAIL in
core/support/requests.jac: "<tenant id>|<request id>|<address>"), and this module's job
sends them every AFRICINEMAS_MAIL_SECONDS, as the ticket email's does
(core/booking/ticket_delivery.jac): never inside a request, a failed send stays queued,
SENDING keeps two servers from sending the same one. The email says what the request
is about, quotes our latest message, and links to the conversation in the back office,
where the reply is read and answered; it carries no screenshot.
"""

import os;
import html;
import from email.utils { formataddr }
import from core.claims { claim, release, claims_in }
import from core.tenancy.principal { fresh_node_id, node_id }
import from core.notify.mailer { OutgoingMail, send, from_address }
import from core.site { main_address }
import from core.support.names { REPLY_MAIL }
import from core.support.requests { CATEGORIES, request_of }

glob SENDING: str = "support-reply-mail-sending",
     SENDING_S: int = 120,
     QUOTE_MAX: int = 1000,
     MAIL_SECONDS: int = int(os.environ.get("AFRICINEMAS_MAIL_SECONDS", "5"));

def reply_mail(cinema_name: str, slug: str, request: any, to: str) -> OutgoingMail {  # jac:ignore[W1037]
    # The email for our latest message on `request`.
    ours = [
        m
        for m in request.messages
        if m["side"] == "africinemas"
    ];
    said = ours[-1]["text"] if ours else "";
    quote = said if len(said) <= QUOTE_MAX else said[:QUOTE_MAX] + "…";
    about: str = str(CATEGORIES.get(request.category, "") or request.category).lower();
    link = f"{main_address()}/app/{slug}/help/{node_id(request)}";
    text = (
        f"AfriCinemas replied to {cinema_name}'s help request about {about}:\n\n"
        + (f"{quote}\n\n" if quote else "(A screenshot.)\n\n")
        + f"Read it and reply in your back office:\n{link}\n"
    );
    # Everything shown in the HTML is escaped: the cinema's name, and what we wrote.
    (name_html, about_html) = (html.escape(cinema_name), html.escape(about));
    (quote_html, link_html) = (html.escape(quote), html.escape(link));
    said_html = (
        f'<blockquote style="white-space:pre-wrap">{quote_html}</blockquote>'
            if quote
            else "<p>(A screenshot.)</p>"
    );
    body = (
        f"<p>AfriCinemas replied to {name_html}'s help request about {about_html}:</p>"
        + said_html
        + f'<p><a href="{link_html}">Read it and reply in your back office</a></p>'
    );
    return OutgoingMail(
        to=to,
        sender=formataddr(("AfriCinemas", from_address())),
        subject=f"AfriCinemas replied about {about}",
        text=text,
        html=body
    );
}

def send_support_due -> int {
    # Sends every queued reply email; returns how many went.
    sent = 0;
    for (key, queued, _) in claims_in(REPLY_MAIL) {
        mine = fresh_node_id();
        if claim(SENDING, key, mine, SENDING_S) != mine {
            continue;
        }
        try {
            (_, request_id, address) = queued.split("|", 2);
            found = request_of(request_id);
            if found is None {
                release(REPLY_MAIL, key, queued);
                continue;
            }
            (cinema, request) = found;
            if send(reply_mail(cinema.name, cinema.slug, request, address)) {
                release(REPLY_MAIL, key, queued);
                sent += 1;
            }
        } finally {
            release(SENDING, key, mine);
        }
    }
    return sent;
}

@schedule(trigger=ScheduleTrigger.STATIC, interval=MAIL_SECONDS)
def send_support_mail {
    # Runs as Jac's system identity on every server copy; SENDING keeps one per email.
    send_support_due();
}
