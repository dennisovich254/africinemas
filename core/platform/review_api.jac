"""Reviewing a cinema's verification (P14.5, ADR-0071), in the platform console.

For reviewers and super admins (platform.review):
- platform_reviews(): the cinemas waiting for a review, oldest submission first;
- platform_review(slug): one cinema's details and which files it sent, with the
  reviewer's checklist;
- platform_review_file(slug, item): one of its files, to look at (each look is in the
  platform's audit log: ID photos are personal data);
- platform_decide(slug, decision, reasons): approve (the cinema goes active and public,
  with the Verified badge), ask for changes (the owner's page reopens with the
  reasons) or reject (it stays private, with the reasons). Logged, and emailed to the
  cinema's owners.

The email is queued (DECISION_MAIL) and sent by this module's job, never inside a
request.
"""

import os;
import json;
import html;
import from email.utils { formataddr }
import from core.claims { claim, release, claims_in }
import from core.catalog.answers { Refused, answer }
import from core.tenancy.models { Tenant }
import from core.tenancy.open_cinema { tenant_by_id }
import from core.tenancy.principal { node_id, fresh_node_id }
import from core.tenancy.verification {
    record_of,
    file_answer,
    decide,
    TEXT_FIELDS,
    FILES,
    BUSINESS_TYPES
}
import from core.audit.log { platform_audited }
import from core.platform.staff_api { require_platform }
import from core.platform.cinemas_api { all_cinemas, owners_of }
import from core.notify.mailer { OutgoingMail, send, from_address }
import from core.site { main_address }

glob REVIEW: str = "platform.review",
     DECISION_MAIL: str = "verification-decision-mail",
     SENDING: str = "verification-decision-sending",
     SENDING_S: int = 120,
     MAIL_SECONDS: int = int(os.environ.get("AFRICINEMAS_MAIL_SECONDS", "5")),
     # What the reviewer checks against the documents.
     CHECKLIST: list[str] = [
         "The name on the ID matches the owner's legal name, and the ID number matches.",
         "The business's registered name matches the registration and KRA PIN certificates.",
         "The KRA PIN matches the KRA PIN certificate.",
         "The county permit is current and names this business.",
         "The premises address is in Kenya."
     ],
     ACTIONS: dict[str, str] = {
         "approve": "platform.verification_approved",
         "changes": "platform.verification_changes_requested",
         "reject": "platform.verification_rejected"
     };

def _find(slug: str) -> Tenant {
    wanted = slug.strip().lower() if isinstance(slug, str) else "";
    for c in all_cinemas() {
        if c.slug == wanted {
            return c;
        }
    }
    raise Refused("not_found", "No such cinema.");
}

def _queue -> dict[str, any] {  # jac:ignore[W1037]
    require_platform(REVIEW);
    waiting: list[dict[str, str]] = [];
    for c in all_cinemas() {
        kept = record_of(c);
        if kept["status"] == "submitted" {
            waiting.append(
                {
                    "slug": c.slug,
                    "name": c.name,
                    "submitted_at": kept["submitted_at"],
                    "registered_name": kept["details"].get("registered_name", "")
                }
            );
        }
    }
    waiting.sort(key=lambda (w: dict[str, str]) -> str { return w["submitted_at"]; });
    return {"ok": True, "reviews": waiting};
}

def _review(slug: str) -> dict[str, any] {  # jac:ignore[W1037]
    require_platform(REVIEW);
    cinema = _find(slug);
    kept = record_of(cinema);
    return {
        "ok": True,
        "cinema": {"slug": cinema.slug, "name": cinema.name, "state": cinema.state},
        "owners": owners_of(cinema),
        "status": kept["status"],
        "submitted_at": kept["submitted_at"],
        "decided_at": kept["decided_at"],
        "reviewed_by": kept["reviewed_by"],
        "reasons": kept["reasons"],
        "details": kept["details"],
        "business_type": BUSINESS_TYPES.get(
            kept["details"].get("business_type", ""), ""
        ),
        "labels": {k: v[0] for (k, v) in TEXT_FIELDS.items()},
        "files": [
            {
                "item": item,
                "label": label,
                "type": kept["files"].get(item, {}).get("type", ""),
                "uploaded_at": kept["files"].get(item, {}).get("uploaded_at", ""),
                # Deleted by the retention rules (P14.5b), and when.
                "removed_at": kept["files_removed"].get(item, "")
            } for (item, label) in FILES.items()
        ],
        "checklist": CHECKLIST
    };
}

def decision_mail(
    cinema: Tenant, decision: str, reasons: list[str], to: str
) -> OutgoingMail {
    # What the owner is told: the decision, any reasons, and where to go next.
    office = f"{main_address()}/app/{cinema.slug}/verification";
    if decision == "approve" {
        subject = f"{cinema.name} is verified and public";
        lead = f"AfriCinemas has verified {cinema.name}. Your storefront is public now, and customers can book.";
    } elif decision == "changes" {
        subject = f"{cinema.name}: a few changes before it goes public";
        lead = f"AfriCinemas has looked at {cinema.name}'s details and needs a few changes before it can go public:";
    } else {
        subject = f"{cinema.name} couldn't be verified";
        lead = f"AfriCinemas couldn't verify {cinema.name}, so it won't go public:";
    }
    listed = "".join([f"- {r}\n" for r in reasons]);
    text = f"{lead}\n\n{listed}\nYour cinema's Verification page: {office}\n\nTickets by AfriCinemas\n";
    items = "".join([f"<li>{html.escape(r)}</li>" for r in reasons]);
    body = (
        f"<p>{html.escape(lead)}</p>"
        + (f"<ul>{items}</ul>" if items else "")
        + f'<p><a href="{html.escape(office)}">Open your Verification page</a></p>'
    );
    return OutgoingMail(
        to=to,
        sender=formataddr(("AfriCinemas", from_address())),
        subject=subject,
        text=text,
        html=body
    );
}

def _decide(
    slug: str, decision: str, reasons: list[str], reviewer: str
) -> dict[str, any] {  # jac:ignore[W1037]
    cinema = _find(slug);
    decide(cinema, decision, reasons, reviewer);
    said = record_of(cinema)["reasons"];
    for address in owners_of(cinema) {
        claim(
            DECISION_MAIL,
            fresh_node_id(),
            json.dumps(
                {
                    "cinema": node_id(cinema),
                    "decision": decision,
                    "reasons": said,
                    "to": address
                }
            )
        );
    }
    return _review(slug);
}

def:protect platform_reviews -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _queue(); });  # jac:ignore[W1037]
}

def:protect platform_review(slug: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _review(slug); });  # jac:ignore[W1037]
}

def:protect platform_review_file(slug: str, item: str) -> dict[str, any] {  # jac:ignore[W1037]
    try {
        me = require_platform(REVIEW);
        cinema = _find(slug);
    } except Refused as e {
        return answer(lambda -> any { raise e; });  # jac:ignore[W1037]
    }
    return platform_audited(
        me.root_id,
        me.email,
        "platform.verification_file_viewed",
        "cinema",
        node_id(cinema),
        lambda -> any { return file_answer(cinema, item); }  # jac:ignore[W1037]
    );
}

def:protect platform_decide(
    slug: str, decision: str, reasons: list[str]
) -> dict[str, any] {  # jac:ignore[W1037]
    try {
        me = require_platform(REVIEW);
        cinema = _find(slug);
    } except Refused as e {
        return answer(lambda -> any { raise e; });  # jac:ignore[W1037]
    }
    return platform_audited(
        me.root_id,
        me.email,
        ACTIONS.get(decision, "platform.verification_decided"),
        "cinema",
        node_id(cinema),
        lambda -> any { return _decide(slug, decision, reasons, me.email); }  # jac:ignore[W1037]
    );
}

def send_decisions_due -> int {
    # Sends every queued decision email; returns how many went.
    sent = 0;
    for (key, queued, _) in claims_in(DECISION_MAIL) {
        mine = fresh_node_id();
        if claim(SENDING, key, mine, SENDING_S) != mine {
            continue;
        }
        try {
            mail: dict[str, any] = json.loads(queued);  # jac:ignore[W1037]
            cinema = tenant_by_id(str(mail.get("cinema", "")));
            if cinema is None {
                release(DECISION_MAIL, key, queued);
                continue;
            }
            if send(
                decision_mail(cinema, mail["decision"], mail["reasons"], mail["to"])
            ) {
                release(DECISION_MAIL, key, queued);
                sent += 1;
            }
        } finally {
            release(SENDING, key, mine);
        }
    }
    return sent;
}

@schedule(trigger=ScheduleTrigger.STATIC, interval=MAIL_SECONDS)
def send_decision_mail {
    # Runs as Jac's system identity on every server copy; SENDING keeps one per email.
    send_decisions_due();
}
