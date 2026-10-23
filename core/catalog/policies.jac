"""A cinema's policies (P14.3b, ADR-0067): pages its storefront links from every footer.

Six kinds (KINDS): terms of ticket sale, privacy (Kenya Data Protection Act, 2019),
refunds and cancellations, house rules, accessibility, and a page explaining the KFCB
age ratings. Each is written in the back office (Settings -> Policies), starting, if
the cinema likes, from a plain-language template we offer with its name and contact
filled in. A template is a starting point, not advice: a policy is only published once
someone ticks that they've read it and it's right for their cinema.

Text is kept as typed, in a small plain format the storefront draws as React text
(never as HTML): a blank line between paragraphs, "## " starts a heading and "- " a
list item. Terms, privacy and refunds are required (REQUIRED): missing_policies names
those not yet published, for submitting a cinema for review (14.4).
"""

import re;
import from core.clock { now }
import from core.authz.context { scoped }
import from core.tenancy.models { Tenant }
import from core.tenancy.groups { attach_to_tenant }
import from core.tenancy.principal { node_id, act_as, restore, flush_now }
import from core.catalog.answers { Refused, answer }
import from core.audit.log { audited }
import from core.tenancy.open_cinema { open_cinema }
import from core.tenancy.responses { NOT_FOUND }
import from core.catalog.site_info { site_info_of }

glob CONFIGURE: str = "tenant.settings.update",
     KINDS: list[tuple[str, str]] = [
         ("terms", "Terms of ticket sale"),
         ("privacy", "Privacy policy"),
         ("refunds", "Refunds and cancellations"),
         ("house_rules", "House rules"),
         ("accessibility", "Accessibility"),
         ("age_ratings", "Age ratings")
     ],
     REQUIRED: list[str] = ["terms", "privacy", "refunds"],
     TEXT_MAX: int = 20000,
     # Control characters but tab and newline.
     CONTROL: str = r"[\x00-\x08\x0b-\x1f\x7f]";

node Policies {
    # The cinema's policies by kind: {"text", "published", "updated_at"}. Owned by its
    # principal.
    has tenant_id: str,
        data: dict[str, any] = {};  # jac:ignore[W1037]
}

def title_of(kind: str) -> str {
    for (k, title) in KINDS {
        if k == kind {
            return title;
        }
    }
    return "";
}

def _contact(info: dict[str, any]) -> str {  # jac:ignore[W1037]
    # How the templates say to reach the cinema: its email and phone, as filled in.
    ways = [
        w
        for w in [info.get("email", ""), info.get("phone", "")]
        if w
    ];
    return " or ".join(ways)
        if ways
        else "the contact details at the bottom of this page";
}

def template_for(kind: str, cinema: str, info: dict[str, any]) -> str {  # jac:ignore[W1037]
    # A plain-language starting point for a policy, with the cinema's name and contact.
    name = info.get("business_name", "") or cinema;
    reach = _contact(info);
    texts: dict[str, str] = {
        "terms": f"""These terms apply when you buy tickets from {name} on this website.

## Your booking
- Your tickets are for the film, date, time and seats shown when you pay.
- Prices are in Kenyan shillings. A booking fee, if any, is shown before you pay.
- A booking is confirmed once payment succeeds. We send your tickets by email and you can find them under My tickets.

## At the cinema
- Show your ticket's QR code at the door, on your phone or printed. Each ticket lets one person in, once.
- Films have age ratings set by the Kenya Film Classification Board. We may ask for ID and refuse entry to anyone below a film's rating.
- Please arrive before the film starts. Late entry may not be possible for every film.
- Our house rules apply inside the cinema.

## Changes and refunds
If we cancel or move a showing, we'll contact you and offer a refund or another showing. Our refunds and cancellations policy explains the rest.

## Contact
Questions about a booking? Reach {name} at {reach}.
""",
        "privacy": f"""This policy explains what personal data {name} collects when you book with us, and how we use it, under Kenya's Data Protection Act, 2019.

## What we collect
- Your name, email address and phone number, when you book or create an account.
- Your bookings: films, showtimes, seats and what you paid.
- Payment details from M-Pesa: the phone number that paid and the transaction reference. We never see your M-Pesa PIN.

## Why we use it
- To send your tickets, let you in and answer your questions.
- To handle payments and refunds, and to keep the records the law requires.
- To send you offers, only if you agree to it. You can stop them at any time.

## Who we share it with
Our ticketing provider, AfriCinemas, runs this website for us and keeps your data on our behalf. Safaricom processes M-Pesa payments. We don't sell your data.

## How long we keep it
We keep booking and payment records for as long as the law requires, and the rest only as long as we need it.

## Your rights
You can ask to see the data we hold about you, to correct it, or to delete it, and you can object to how we use it. Write to us at {reach}. You can also complain to the Office of the Data Protection Commissioner.
""",
        "refunds": f"""## When we refund you
- If we cancel a showing, or it can't go ahead, you get a full refund, or another showing if you prefer.
- If a showing is moved to another time, you can choose a refund instead.

## When you change your mind
Tickets can't be returned once bought, unless we say otherwise for a showing. If you can't make it, contact us before the film starts and we'll see what we can do.

## How refunds are paid
Refunds go back to the M-Pesa number that paid, usually within 7 days.

## Ask for a refund
Contact {name} at {reach}, with your booking's reference.
""",
        "house_rules": f"""To keep every showing enjoyable for everyone at {name}:

- Food and drinks from outside aren't allowed, unless we say so.
- Recording or photographing the film is against the law and isn't allowed.
- Please keep your phone silent and its screen dark during the film.
- Children must be with an adult, and every film's age rating applies. We may ask for ID.
- Late entry may not be possible once the film has started.
- Lost something? Ask our staff, or contact us at {reach}. We keep lost property for 30 days.

Staff may ask anyone who doesn't follow these rules to leave, without a refund.
""",
        "accessibility": f"""We want everyone to enjoy the films at {name}.

## Getting in
Tell us here what step-free access the building has, where the lifts are, and where the nearest accessible toilet is.

## Seats
Tell us here how many wheelchair spaces each screen has, and whether a companion can sit next to them.

## Subtitles and hearing support
Tell us here which showings have subtitles, and whether you have hearing loops or other support.

## Ask us
Need something we haven't mentioned? Contact us at {reach} before your visit and we'll help.
""",
        "age_ratings": f"""Every film in Kenya is rated by the Kenya Film Classification Board (KFCB). {name} follows these ratings, and staff may ask for ID at the door.

## The ratings
- GE (General Exhibition): suitable for everyone.
- PG (Parental Guidance): suitable for everyone, but parents should check whether it suits younger children.
- 16: not suitable for anyone under 16.
- 18: for adults only, 18 and over.
- R (Restricted): restricted, and not shown to the general public.

## At the door
Anyone below a film's rating won't be let in, even with an adult, and their ticket can't be refunded. If you're not sure about a film, ask us before you book at {reach}.
"""
    };
    return texts.get(kind, "");
}

def clean_text(raw: any) -> str {  # jac:ignore[W1037]
    # The text as it's kept: plain characters, Unix line ends, no trailing blank lines.
    text = raw if isinstance(raw, str) else "";
    text = re.sub(CONTROL, "", text.replace("\r\n", "\n").replace("\r", "\n"));
    return text.strip();
}

def _kept(cinema: Tenant) -> Policies | None {
    if not cinema.policies_id {
        return None;
    }
    try {
        found: any = jobj(cinema.policies_id);  # jac:ignore[W1037]
    } except Exception {
        return None;
    }
    return found if isinstance(found, Policies) else None;
}

def policies_of(cinema: Tenant) -> dict[str, dict[str, any]] {  # jac:ignore[W1037]
    # The cinema's policies by kind, as kept; {} before its first save.
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = _kept(cinema);
        return dict(found.data) if found else {};
    } finally {
        restore(me);
    }
}

def published_policies(cinema: Tenant) -> list[dict[str, str]] {
    # The published ones, in KINDS order, for the footer's links.
    kept = policies_of(cinema);
    return [
        {"kind": kind, "title": title}
        for (kind, title) in KINDS
        if kept.get(kind, {}).get("published", False)
    ];
}

def missing_from(kept: dict[str, dict[str, any]]) -> list[str] {  # jac:ignore[W1037]
    # The required policies not published among `kept` (policies by kind).
    return [
        kind
        for kind in REQUIRED
        if not kept.get(kind, {}).get("published", False)
    ];
}

def missing_policies(cinema: Tenant) -> list[str] {
    # The required policies the cinema hasn't published yet (for 14.4's review).
    return missing_from(policies_of(cinema));
}

def _listing(cinema: Tenant) -> list[dict[str, any]] {  # jac:ignore[W1037]
    kept = policies_of(cinema);
    info = site_info_of(cinema);
    return [
        {
            "kind": kind,
            "title": title,
            "required": kind in REQUIRED,
            "text": kept.get(kind, {}).get("text", ""),
            "published": kept.get(kind, {}).get("published", False),
            "updated_at": kept.get(kind, {}).get("updated_at", ""),
            "template": template_for(kind, cinema.name, info)
        } for (kind, title) in KINDS
    ];
}

def _get(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, CONFIGURE);
    return {"ok": True, "policies": _listing(scope.tenant)};
}

def _save(
    tenant: str, kind: str, text: str, published: bool, reviewed: bool
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, CONFIGURE);
    if not title_of(kind) {
        raise Refused("unknown_policy", "Choose one of the policies listed.");
    }
    kept_text = clean_text(text);
    if len(kept_text) > TEXT_MAX {
        raise Refused(
            "too_long",
            f"Keep it to {TEXT_MAX} characters or fewer. Shorten it, then save."
        );
    }
    if published and not kept_text {
        raise Refused("empty_policy", "Write the policy before publishing it.");
    }
    if published and not reviewed {
        raise Refused(
            "not_reviewed",
            "Tick that you've read it and it's right for your cinema, then publish."
        );
    }
    cinema: Tenant = scope.tenant;
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = _kept(cinema);
        if found is None {
            made = Policies(tenant_id=scope.ctx.tenant_id);
            cinema ++> made;
            attach_to_tenant(made, cinema);
            cinema.policies_id = node_id(made);
            found = made;
        }
        kept: Policies = found;
        data: dict[str, any] = dict(kept.data);  # jac:ignore[W1037]
        data[kind] = {
            "text": kept_text,
            "published": bool(published),
            "updated_at": now().isoformat()
        };
        kept.data = data;
        flush_now();
    } finally {
        restore(me);
    }
    return {"ok": True, "policies": _listing(cinema)};
}

def:protect policies(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _get(tenant); });  # jac:ignore[W1037]
}

def:protect save_policy(
    tenant: str, kind: str, text: str, published: bool, reviewed: bool
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "policy.saved",
        "policy",
        kind,
        lambda -> any { return _save(tenant, kind, text, published, reviewed); }  # jac:ignore[W1037]
    );
}

def:pub public_policy(slug: str, kind: str) -> dict[str, any] {  # jac:ignore[W1037]
    # One published policy of a public cinema; not found if it isn't published.
    cinema = open_cinema(slug);
    if cinema is None {
        return NOT_FOUND;
    }
    kept = policies_of(cinema).get(kind, {});
    if not kept.get("published", False) or not title_of(kind) {
        return NOT_FOUND;
    }
    return {
        "ok": True,
        "kind": kind,
        "title": title_of(kind),
        "text": kept.get("text", ""),
        "updated_at": kept.get("updated_at", "")
    };
}
