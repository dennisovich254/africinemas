"""A cinema's public information (P14.3a, ADR-0066): what every storefront page shows.

Set in the back office (Settings -> Website information) by staff who change the
cinema's settings, shown to everyone on the cinema's storefront: in the footer of
every page, which no design can leave out (web/storefront/FooterInfo.jac), directions
and parking where visitors plan their trip, and booking notes before they choose
tickets. Plain text only, like the home page (§41): nothing with markup is kept, and
links are built here from what's typed, never taken as typed:
- phone and WhatsApp: Kenyan numbers, kept as +254...; WhatsApp links are wa.me;
- social media: handles, made into links to the network itself;
- email: checked for its shape.

parse_info reports every problem at once, each with the field it's about.
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
import from core.tenancy.reserved_words {
    name_claims,
    text_claims,
    NAME_MESSAGE,
    TEXT_MESSAGE
}

glob CONFIGURE: str = "tenant.settings.update",
     TEXT_LIMITS: dict[str, int] = {
         "business_name": 120,
         "address": 200,
         "support_hours": 120,
         "directions": 600,
         "parking": 300,
         "payment_note": 200
     },
     SOCIALS: dict[str, str] = {
         "facebook": "https://www.facebook.com/{}",
         "instagram": "https://www.instagram.com/{}",
         "x": "https://x.com/{}",
         "tiktok": "https://www.tiktok.com/@{}",
         "youtube": "https://www.youtube.com/@{}"
     },
     SOCIAL_LABELS: dict[str, str] = {
         "facebook": "Facebook",
         "instagram": "Instagram",
         "x": "X",
         "tiktok": "TikTok",
         "youtube": "YouTube"
     },
     HANDLE_PATTERN: str = r"[A-Za-z0-9._-]{1,50}",
     EMAIL_PATTERN: str = r"[^@\s<>]{1,64}@[^@\s<>]{1,190}\.[^@\s<>]{2,63}",
     NOTES_MAX: int = 10,
     NOTE_NAME_MAX: int = 40,
     NOTE_TEXT_MAX: int = 160,
     MARKUP: list[str] = ["<", ">"];

node SiteInfo {
    # The cinema's public information, as parse_info keeps it. Owned by its principal.
    has tenant_id: str,
        data: dict[str, any] = {},  # jac:ignore[W1037]
        updated_at: str = "";
}

obj InfoProblem {
    has field: str,
        code: str,
        message: str;
}

def empty_info -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "business_name": "",
        "address": "",
        "phone": "",
        "email": "",
        "whatsapp": "",
        "support_hours": "",
        "socials": {k: "" for k in SOCIALS},
        "directions": "",
        "parking": "",
        "ticket_notes": [],
        "payment_note": "",
        # Whether the cinema sends offers to customers who ask (P14.3c): checkout and
        # sign-up then offer the box.
        "sends_offers": False
    };
}

def kenyan_number(text: str) -> str {
    # A Kenyan phone number as +254XXXXXXXXX (mobile 07/01, or +254/254), or "".
    digits = re.sub(r"[\s\-()]", "", text or "");
    if digits.startswith("+") {
        digits = digits[1:];
    }
    if re.fullmatch(r"0[17]\d{8}", digits) {
        return "+254" + digits[1:];
    }
    if re.fullmatch(r"254[17]\d{8}", digits) {
        return "+" + digits;
    }
    return "";
}

def _text(raw: any, field: str, limit: int, problems: list[InfoProblem]) -> str {  # jac:ignore[W1037]
    text = " ".join(raw.split())
        if isinstance(raw, str) and field != "directions"
        else (raw.strip() if isinstance(raw, str) else "");
    if any([m in text for m in MARKUP]) {
        problems.append(
            InfoProblem(
                field=field, code="markup", message="Use plain text, without < or >."
            )
        );
        return "";
    }
    if len(text) > limit {
        problems.append(
            InfoProblem(
                field=field,
                code="too_long",
                message=f"Keep it to {limit} characters or fewer."
            )
        );
        return "";
    }
    # Only AfriCinemas shows the Verified badge (P14.5).
    claims = name_claims(text) if field == "business_name" else text_claims(text);
    if claims {
        problems.append(
            InfoProblem(
                field=field,
                code="badge_claim",
                message=NAME_MESSAGE if field == "business_name" else TEXT_MESSAGE
            )
        );
        return "";
    }
    return text;
}

def parse_info(raw: any) -> tuple[dict[str, any], list[InfoProblem]] {  # jac:ignore[W1037]
    # The information as it's kept, and every problem with what was sent.
    given: dict[str, any] = raw if isinstance(raw, dict) else {};  # jac:ignore[W1037]
    problems: list[InfoProblem] = [];
    info = empty_info();
    for (field, limit) in TEXT_LIMITS.items() {
        info[field] = _text(given.get(field, ""), field, limit, problems);
    }
    for field in ["phone", "whatsapp"] {
        typed = str(given.get(field, "") or "").strip();
        if typed {
            info[field] = kenyan_number(typed);
            if not info[field] {
                problems.append(
                    InfoProblem(
                        field=field,
                        code="invalid_phone",
                        message="Enter a Kenyan number, like 0712 345 678."
                    )
                );
            }
        }
    }
    typed_email = str(given.get("email", "") or "").strip().lower();
    if typed_email {
        if re.fullmatch(EMAIL_PATTERN, typed_email) {
            info["email"] = typed_email;
        } else {
            problems.append(
                InfoProblem(
                    field="email",
                    code="invalid_email",
                    message="Enter an email address, like hello@example.com."
                )
            );
        }
    }
    sent_socials: any = given.get("socials");  # jac:ignore[W1037]
    socials: dict[str, any] = sent_socials if isinstance(sent_socials, dict) else {};  # jac:ignore[W1037]
    for network in SOCIALS {
        handle = str(socials.get(network, "") or "").strip().removeprefix("@");
        if handle and not re.fullmatch(HANDLE_PATTERN, handle) {
            problems.append(
                InfoProblem(
                    field=f"socials.{network}",
                    code="invalid_handle",
                    message="Enter the account's name only, like anga_cinemas, not a link."
                )
            );
            continue;
        }
        info["socials"][network] = handle;
    }
    sent_notes: any = given.get("ticket_notes");  # jac:ignore[W1037]
    notes: list[any] = sent_notes if isinstance(sent_notes, list) else [];  # jac:ignore[W1037]
    if len(notes) > NOTES_MAX {
        problems.append(
            InfoProblem(
                field="ticket_notes",
                code="too_many",
                message=f"Keep it to {NOTES_MAX} notes."
            )
        );
        notes = notes[:NOTES_MAX];
    }
    for (i, note) in enumerate(notes) {
        item: dict[str, any] = note if isinstance(note, dict) else {};  # jac:ignore[W1037]
        name = _text(
            item.get("name", ""), f"ticket_notes.{i}.name", NOTE_NAME_MAX, problems
        );
        text = _text(
            item.get("note", ""), f"ticket_notes.{i}.note", NOTE_TEXT_MAX, problems
        );
        if name and text {
            info["ticket_notes"].append({"name": name, "note": text});
        } elif name or text {
            problems.append(
                InfoProblem(
                    field=f"ticket_notes.{i}",
                    code="incomplete",
                    message="Give the ticket's name and what it means."
                )
            );
        }
    }
    info["sends_offers"] = given.get("sends_offers", False) is True;
    return (info, problems);
}

def public_view(info: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    # What the storefront shows: links built here, empty fields left out.
    socials: dict[str, str] = info.get("socials") or {};
    whatsapp: str = info.get("whatsapp") or "";
    return {
        "business_name": info.get("business_name") or "",
        "address": info.get("address") or "",
        "phone": info.get("phone") or "",
        "email": info.get("email") or "",
        "whatsapp": whatsapp,
        "whatsapp_url": f"https://wa.me/{whatsapp[1:]}" if whatsapp else "",
        "support_hours": info.get("support_hours") or "",
        "socials": [
            {
                "network": k,
                "label": SOCIAL_LABELS[k],
                "handle": socials[k],
                "url": SOCIALS[k].format(socials[k])
            }
            for k in SOCIALS
            if socials.get(k)
        ],
        "directions": info.get("directions") or "",
        "parking": info.get("parking") or "",
        "ticket_notes": info.get("ticket_notes") or [],
        "payment_note": info.get("payment_note") or "",
        "sends_offers": bool(info.get("sends_offers", False))
    };
}

def site_info_of(cinema: Tenant) -> dict[str, any] {  # jac:ignore[W1037]
    # The cinema's information as kept, or an empty one before its first save.
    if not cinema.site_info_id {
        return empty_info();
    }
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found: any = jobj(cinema.site_info_id);  # jac:ignore[W1037]
    } except Exception {
        found = None;
    } finally {
        restore(me);
    }
    if not isinstance(found, SiteInfo) {
        return empty_info();
    }
    kept: dict[str, any] = dict(empty_info());  # jac:ignore[W1037]
    kept.update(found.data);
    return kept;
}

def _get(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, CONFIGURE);
    return {"ok": True, "info": site_info_of(scope.tenant)};
}

def _save(tenant: str, info: any) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, CONFIGURE);
    (clean, problems) = parse_info(info);
    if problems {
        raise Refused(
            "invalid_info",
            "Some of this needs fixing before it can be saved.",
            {
                "problems": [
                    {"field": p.field, "code": p.code, "message": p.message}
                    for p in problems
                ]
            }
        );
    }
    cinema: Tenant = scope.tenant;
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found: any = jobj(cinema.site_info_id) if cinema.site_info_id else None;  # jac:ignore[W1037]
        if not isinstance(found, SiteInfo) {
            made = SiteInfo(tenant_id=scope.ctx.tenant_id);
            cinema ++> made;
            attach_to_tenant(made, cinema);
            cinema.site_info_id = node_id(made);
            found = made;
        }
        kept: SiteInfo = found;
        kept.data = clean;
        kept.updated_at = now().isoformat();
        flush_now();
    } finally {
        restore(me);
    }
    return {"ok": True, "info": clean};
}

def:protect site_info(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _get(tenant); });  # jac:ignore[W1037]
}

def:protect save_site_info(tenant: str, info: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "site_info.saved",
        "site_info",
        "",
        lambda -> any { return _save(tenant, info); }  # jac:ignore[W1037]
    );
}

def:pub public_site_info(slug: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The cinema's public information alone (no theme or logo), for pages that need
    # only it: directions on the Cinemas page, booking notes beside a showtime.
    cinema = open_cinema(slug);
    if cinema is None {
        return NOT_FOUND;
    }
    return {"ok": True, "info": public_view(site_info_of(cinema))};
}
