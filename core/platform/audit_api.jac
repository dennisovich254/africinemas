"""The platform's own audit log (P13.3): what AfriCinemas' team did, and what was refused.

Endpoints listed in tests/isolation/registry.jac with the "platform" scope.

- platform_audit_log(limit, before, action, search, cinema): the platform's events,
  newest first, `limit` at a time (1 to MAX_LIMIT), paged as the cinema audit log is
  (ADR-0027): `before` is the last event id of the page before and `next` the one to
  pass for the next page; `total` counts every match. `action` keeps one action,
  `search` the events whose actor, target or note contains it, and `cinema` (a slug)
  those about that cinema. For super admins (platform.audit): it's the record of what
  the team does.
- platform_signed_in(): the sign-in page's report that a platform member has just
  signed in (P13.3): Jac's sign-in itself runs no code of ours, so wrong passwords
  aren't in this log.

Events are written by core/audit/log.jac only (platform_audited, platform_record). No
endpoint changes or deletes one.
"""

import from core.catalog.answers { Refused, answer }
import from core.tenancy.models { Tenant }
import from core.tenancy.registry { lookup_slug }
import from core.tenancy.open_cinema { tenant_by_id }
import from core.audit.log {
    platform_events,
    count_platform_events,
    has_platform_event,
    platform_record
}
import from core.platform.staff_api { require_platform, caller }

glob MAX_LIMIT: int = 100;

def _on(event: dict[str, str], names: dict[str, Tenant | None]) -> dict[str, str] {
    # The event, with the cinema it's about named, when it's about one.
    shown = dict(event);
    shown["cinema"] = "";
    shown["cinema_slug"] = "";
    if event.get("resource_type") == "cinema" {
        key = event.get("resource_id", "");
        if key not in names {
            names[key] = tenant_by_id(key);
        }
        found = names[key];
        if found is not None {
            shown["cinema"] = found.name;
            shown["cinema_slug"] = found.slug;
        }
    }
    return shown;
}

def _log(
    limit: int, before: str, action: str, search: str, cinema: str
) -> dict[str, any] {  # jac:ignore[W1037]
    require_platform("platform.audit");
    if not isinstance(limit, int) or limit < 1 or limit > MAX_LIMIT {
        raise Refused("bad_limit", f"Ask for 1 to {MAX_LIMIT} events at a time.");
    }
    if before and not has_platform_event(before) {
        raise Refused("not_found", "That page of the log isn't there any more.");
    }
    about = "";
    if cinema {
        about = lookup_slug(cinema.strip().lower()) or "";
        if not about {
            raise Refused("not_found", "No such cinema.");
        }
    }
    wanted = search.strip()[:100] if isinstance(search, str) else "";
    found = platform_events(before, limit + 1, action or "", wanted, about);
    names: dict[str, Tenant | None] = {};
    page = [_on(e, names) for e in found[:limit]];
    return {
        "ok": True,
        "events": page,
        "next": page[-1]["event_id"] if len(found) > limit else "",
        "total": count_platform_events(action or "", wanted, about)
    };
}

def _signed_in -> dict[str, any] {  # jac:ignore[W1037]
    me = caller();
    if me is None {
        raise Refused("not_platform", "This area is for AfriCinemas staff.");
    }
    platform_record(
        me.root_id, me.email, "platform.signed_in", "platform_staff", me.email, "ok"
    );
    return {"ok": True};
}

def:protect platform_audit_log(
    limit: int, before: str = "", action: str = "", search: str = "", cinema: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(
        lambda -> any { return _log(limit, before, action, search, cinema); }  # jac:ignore[W1037]
    );
}

def:protect platform_signed_in -> dict[str, any] {  # jac:ignore[W1037]
    return answer(_signed_in);
}
