"""Telling the owner when their verification is viewed or changed (P15.0, DPIA R4).

A stolen owner account could read or change the owner's ID and the business's
documents, and a reviewer opening them is worth knowing about too. So every owner of
the cinema is emailed:
- **changed**: the details saved, a document uploaded, or it was submitted;
- **viewed**: AfriCinemas staff opened one of its documents (the platform audit log
  has who and when).
At most one email of each kind an hour per cinema (a claim for ONCE_S), so a reviewer
opening five documents sends one. They're queued here and sent by send_notices.
"""

import os;
import json;
import html;
import from email.utils { formataddr }
import from core.claims { claim, claims_in, release }
import from core.tenancy.models { Tenant }
import from core.tenancy.membership { records_of }
import from core.tenancy.principal { node_id, act_as, restore, fresh_node_id }
import from core.notify.mailer { OutgoingMail, send, from_address }
import from core.site { main_address }

glob ONCE: str = "verification-notice-sent",
     ONCE_S: int = 3600,
     QUEUE: str = "verification-notice",
     SENDING: str = "verification-notice-sending",
     SENDING_S: int = 120,
     MAIL_SECONDS: int = int(os.environ.get("AFRICINEMAS_MAIL_SECONDS", "5"));

def _owners(cinema: Tenant) -> list[str] {
    # Its active owners' sign-in emails.
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        return [
            m.email
            for m in records_of(cinema)
            if m.status == "active" and "owner" in m.roles and "@" in m.email
        ];
    } finally {
        restore(me);
    }
}

def notice_mail(name: str, slug: str, what: str, to: str) -> OutgoingMail {
    office = f"{main_address()}/app/{slug}/verification";
    if what == "viewed" {
        subject = f"{name}: AfriCinemas opened your verification documents";
        lead = f"Someone at AfriCinemas opened {name}'s verification documents, to check them. Every time they're opened is recorded.";
        warn = "You don't need to do anything. If you have questions, write to help@africinemas.co.ke.";
    } else {
        subject = f"{name}: your verification details changed";
        lead = f"{name}'s verification details or documents were just changed, or sent to AfriCinemas.";
        warn = "If this wasn't you, change your password now and write to help@africinemas.co.ke.";
    }
    text = f"{lead}\n\n{warn}\n\nVerification: {office}\n\nAfriCinemas\n";
    body = f'<p>{html.escape(lead)}</p><p><strong>{html.escape(
        warn
    )}</strong></p><p><a href="{html.escape(
        office
    )}">Open your Verification page</a></p>';
    return OutgoingMail(
        to=to,
        sender=formataddr(("AfriCinemas", from_address())),
        subject=subject,
        text=text,
        html=body
    );
}

def notify_owners(cinema: Tenant, what: str) {
    # Queues the email of kind `what` ("viewed" or "changed") to every owner, unless
    # one went within the hour.
    mine = fresh_node_id();
    if claim(ONCE, f"{node_id(cinema)}:{what}", mine, ONCE_S) != mine {
        return;
    }
    for address in _owners(cinema) {
        claim(
            QUEUE,
            fresh_node_id(),
            json.dumps(
                {
                    "tenant": node_id(cinema),
                    "slug": cinema.slug,
                    "name": cinema.name,
                    "what": what,
                    "to": address
                }
            )
        );
    }
}

def send_notices_due -> int {
    # Sends every queued notice; how many went.
    sent = 0;
    for (key, queued, _) in claims_in(QUEUE) {
        mine = fresh_node_id();
        if claim(SENDING, key, mine, SENDING_S) != mine {
            continue;
        }
        try {
            mail = json.loads(queued);
            if send(
                notice_mail(mail["name"], mail["slug"], mail["what"], mail["to"])
            ) {
                release(QUEUE, key, queued);
                sent += 1;
            }
        } finally {
            release(SENDING, key, mine);
        }
    }
    return sent;
}

@schedule(trigger=ScheduleTrigger.STATIC, interval=MAIL_SECONDS)
def send_notices {
    # Runs as Jac's system identity on every server copy; SENDING keeps one per email.
    send_notices_due();
}
