"""A cinema's branding (P3.8a, architecture §41, §55). Tenant-scoped endpoints, listed in
tests/isolation/registry.jac, plus the public public_branding.

- The owner edits a draft: save_theme (checked by branding.parse_theme, so only token
  values are stored; unreadable colours are repaired and each change reported),
  upload_logo (checked like a poster, kept with its transparency) and remove_logo.
- publish_theme makes the draft the next numbered ThemeVersion and puts it on the
  cinema's storefront; publishing what is already public is refused. rollback_theme
  publishes an earlier version's theme and logo again, as the next version, and makes
  it the draft.
- public_branding(slug) is public (no login): the published theme, its storefront CSS
  (built here from checked tokens only, core/theming/css.jac) and the logo as a data
  URL; the platform default until the cinema publishes.
- suggest_themes asks the model for themes designed from the draft logo (ADR-0043,
  core/theming/suggest.jac): checked and repaired like any theme, never saved until
  the owner picks one, SUGGEST_DAILY a day per cinema.
- Everything but public_branding needs tenant.settings.update. Another cinema's
  branding answers not_found.
"""

import base64;
import logging;
import from core.clock { now }
import from core.authz.context { TenantScope, scoped }
import from core.tenancy.groups { attach_to_tenant }
import from core.tenancy.principal { node_id, act_as, restore, flush_now }
import from core.tenancy.open_cinema { open_cinema }
import from core.tenancy.responses { NOT_FOUND }
import from core.catalog.answers { Refused, answer }
import from core.catalog.storefront { set_branding, branding_of, upcoming }
import from core.catalog.poster { PosterRejected, decode_upload, process_logo }
import from core.theming.tokens {
    DEFAULT_THEME,
    InvalidThemeValue,
    ROLES,
    DISPLAY_FONTS,
    BODY_FONTS,
    RADII,
    SCHEMES
}
import from core.theming.css { theme_css, FONT_STACKS, RADIUS_REM }
import from core.theming.branding { PRESETS, parse_theme, repair_reporting }
import from core.theming.models { Branding, ThemeVersion }
import from core.theming.suggest { suggest_from_logo }
import from core.theming.pattern { draw_pattern as make_pattern }
import from core.theming.pattern {
    PatternFailed,
    DEFAULT_STYLE,
    checked_style,
    choose_style
}
import from core.audit.log { audited }

glob logger = logging.getLogger(__name__),
     CONFIGURE: str = "tenant.settings.update",
     SUGGEST_DAILY: int = 5,
     # A drawing costs about $0.04 and 15 s (ADR-0045).
     PATTERN_DAILY: int = 3;

def _branding(scope: TenantScope) -> Branding | None {
    if not scope.tenant.branding_id {
        return None;
    }
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        found: any = jobj(scope.tenant.branding_id);  # jac:ignore[W1037]
    } except Exception {
        found = None;
    } finally {
        restore(me);
    }
    return found as Branding if isinstance(found, Branding) else None;
}

def _ensure(scope: TenantScope) -> Branding {
    # The cinema's Branding, made on first use. Call as the cinema's principal.
    found = _branding(scope);
    if found is not None {
        return found as Branding;
    }
    made = Branding(tenant_id=scope.ctx.tenant_id);
    scope.tenant ++> made;
    attach_to_tenant(made, scope.tenant);
    # Two first saves both write this, so the database lets only one through.
    scope.tenant.branding_id = node_id(made);
    return made;
}

def _versions(scope: TenantScope, branding: Branding | None) -> list[ThemeVersion] {
    # Published versions, newest first.
    if branding is None {
        return [];
    }
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        found = [branding-->[?:ThemeVersion]];
    } finally {
        restore(me);
    }
    return sorted(
        found, key=lambda (v: ThemeVersion) -> int { return v.version; }, reverse=True
    );
}

def _draft_theme(branding: Branding | None) -> dict[str, any] {  # jac:ignore[W1037]
    if branding is None or not branding.draft {
        return DEFAULT_THEME.as_dict();
    }
    return dict(branding.draft);
}

def _data_url(logo: str) -> str {
    return f"data:image/webp;base64,{logo}" if logo else "";
}

def _view(scope: TenantScope, branding: Branding | None) -> dict[str, any] {  # jac:ignore[W1037]
    versions = _versions(scope, branding);
    latest = versions[0] if versions else None;
    return {
        "draft": {
            "theme": _draft_theme(branding),
            "has_logo": branding is not None and bool(branding.draft_logo),
            "logo": _data_url(branding.draft_logo if branding is not None else ""),
            "pattern": _data_url(
                branding.draft_pattern if branding is not None else ""
            ),
            "pattern_style": (branding.draft_pattern_style or DEFAULT_STYLE)
                if branding is not None
                else DEFAULT_STYLE
        },
        "published": {
            "version": latest.version,
            "theme": latest.theme,
            "has_logo": bool(latest.logo),
            "has_pattern": bool(latest.pattern),
            "published_at": latest.published_at
        }
            if latest is not None
            else None,
        "versions": [
            {
                "version": v.version,
                "name": v.theme.get("name", ""),
                "published_at": v.published_at
            } for v in versions
        ]
    };
}

def _edit_draft(scope: TenantScope, change: any) {  # jac:ignore[W1037]
    # Applies `change` to the cinema's Branding (made on first use) and saves it.
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        branding = _ensure(scope);
        change(branding);
        branding.updated_at = now().isoformat();
        flush_now();
    } finally {
        restore(me);
    }
}

def _get_branding(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, CONFIGURE);
    return {
        "ok": True,
        "branding": _view(scope, _branding(scope)),
        "presets": [p.as_dict() for p in PRESETS],
        # What the Branding page may offer, so it never keeps its own copy (P3.8b).
        "options": {
            "roles": ROLES,
            "display_fonts": DISPLAY_FONTS,
            "body_fonts": BODY_FONTS,
            "radii": RADII,
            "schemes": SCHEMES,
            "font_stacks": FONT_STACKS,
            "radius_rem": RADIUS_REM
        }
    };
}

def _save_theme(tenant: str, theme: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, CONFIGURE);
    try {
        parsed = parse_theme(theme);
    } except InvalidThemeValue as e {
        raise Refused("invalid_theme", str(e));
    }
    (fixed, changes) = repair_reporting(parsed);
    stored = fixed.as_dict();
    def _set(b: Branding) {
        b.draft = stored;
    }
    _edit_draft(scope, _set);
    return {"ok": True, "theme": stored, "adjusted": changes};
}

def _upload_logo(tenant: str, content_type: str, data_base64: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, CONFIGURE);
    try {
        webp = process_logo(decode_upload(data_base64), content_type);
    } except PosterRejected as e {
        raise Refused(e.code, e.message);
    }
    encoded = base64.b64encode(webp).decode();
    def _set(b: Branding) {
        b.draft_logo = encoded;
    }
    _edit_draft(scope, _set);
    return {"ok": True};
}

def _programme(scope: TenantScope) -> str {
    # What the cinema shows, for the model's home page layout choice: counts only.
    shows = upcoming(scope.tenant);
    if not shows {
        return "No showtimes published yet.";
    }
    films = {str(s.movie.get("movie_id") or s.movie.get("title", "")) for s in shows};
    venues = {str(s.venue.get("venue_id") or s.venue.get("name", "")) for s in shows};
    return f"{len(films)} films with {len(shows)} showtimes coming up, at {len(
        venues
    )} venue(s).";
}

def _suggest_themes(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, CONFIGURE);
    branding = _branding(scope);
    if branding is None or not branding.draft_logo {
        raise Refused("no_logo", "Upload your logo first, then ask for theme ideas.");
    }
    logo = branding.draft_logo;
    today = now().date().isoformat();
    used = branding.suggest_count if branding.suggest_day == today else 0;
    if used >= SUGGEST_DAILY {
        raise Refused(
            "suggest_limit",
            f"You've asked for theme ideas {SUGGEST_DAILY} times today. Try again tomorrow."
        );
    }
    # Counted before the model call, so a slow or failed call still counts.
    def _count(b: Branding) {
        b.suggest_day = today;
        b.suggest_count = used + 1;
    }
    _edit_draft(scope, _count);
    found = suggest_from_logo(
        base64.b64decode(logo), scope.tenant.name, _programme(scope)
    );
    return {
        "ok": True,
        "proposals": found["proposals"],
        "colours": found["colours"],
        "from_ai": found["from_ai"],
        "remaining": SUGGEST_DAILY - used - 1
    };
}

def _draw_pattern(tenant: str, theme: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    # A pattern of the logo's motifs in `theme`'s colours (the theme being edited, saved
    # or not), kept as the draft's pattern: private until published (ADR-0045).
    scope = scoped(tenant, CONFIGURE);
    branding = _branding(scope);
    if branding is None or not branding.draft_logo {
        raise Refused(
            "no_logo", "Upload your logo first, then draw a pattern from it."
        );
    }
    logo = branding.draft_logo;
    try {
        parsed = parse_theme(theme);
    } except InvalidThemeValue as e {
        raise Refused("invalid_theme", str(e));
    }
    today = now().date().isoformat();
    used = branding.pattern_count if branding.pattern_day == today else 0;
    if used >= PATTERN_DAILY {
        raise Refused(
            "pattern_limit",
            f"You've drawn {PATTERN_DAILY} patterns today. Try again tomorrow."
        );
    }
    # Counted before the drawing, so a slow or failed one still counts.
    def _count(b: Branding) {
        b.pattern_day = today;
        b.pattern_count = used + 1;
    }
    _edit_draft(scope, _count);
    try {
        webp = make_pattern(base64.b64decode(logo), parsed);
    } except PatternFailed as e {
        logger.warning("pattern drawing failed: %s", str(e)[:300]);
        raise Refused(
            "pattern_failed",
            "We couldn't draw a pattern just now. Try again in a minute."
        );
    }
    encoded = base64.b64encode(webp).decode();
    # The model picks how the storefront wears this drawing; the owner may switch.
    style = choose_style(base64.b64decode(logo), webp);
    def _keep(b: Branding) {
        b.draft_pattern = encoded;
        b.draft_pattern_style = style;
    }
    _edit_draft(scope, _keep);
    return {
        "ok": True,
        "pattern": _data_url(encoded),
        "style": style,
        "remaining": PATTERN_DAILY - used - 1
    };
}

def _remove_pattern(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, CONFIGURE);
    def _clear(b: Branding) {
        b.draft_pattern = "";
    }
    _edit_draft(scope, _clear);
    return {"ok": True};
}

def _set_pattern_style(tenant: str, style: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, CONFIGURE);
    try {
        chosen = checked_style(style);
    } except ValueError as e {
        raise Refused("invalid_style", str(e));
    }
    def _set(b: Branding) {
        b.draft_pattern_style = chosen;
    }
    _edit_draft(scope, _set);
    return {"ok": True, "style": chosen};
}

def _remove_logo(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, CONFIGURE);
    def _set(b: Branding) {
        b.draft_logo = "";
    }
    _edit_draft(scope, _set);
    return {"ok": True};
}

def _publish(
    scope: TenantScope,
    theme: dict[str, any],  # jac:ignore[W1037]
    logo: str,
    pattern: str = "",
    style: str = ""
) -> int {
    # Publishes `theme`, `logo` and the pattern as the next version; returns its number.
    shown_style = (style or DEFAULT_STYLE) if pattern else "";
    stamp = now().isoformat();
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        branding = _ensure(scope);
        branding.version += 1;  # makes concurrent publishes clash (see models)
        published = ThemeVersion(
            tenant_id=scope.ctx.tenant_id,
            version=branding.version,
            theme=theme,
            logo=logo,
            pattern=pattern,
            pattern_style=shown_style,
            published_at=stamp
        );
        branding ++> published;
        attach_to_tenant(published, scope.tenant);
        flush_now();
    } finally {
        restore(me);
    }
    set_branding(
        scope.tenant,
        {
            "version": published.version,
            "theme": theme,
            "logo": logo,
            "pattern": pattern,
            "pattern_style": shown_style
        }
    );
    return published.version;
}

def _publish_theme(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, CONFIGURE);
    branding = _branding(scope);
    theme = _draft_theme(branding);
    logo = branding.draft_logo if branding is not None else "";
    pattern = branding.draft_pattern if branding is not None else "";
    style = (branding.draft_pattern_style or DEFAULT_STYLE)
        if branding is not None
        else "";
    versions = _versions(scope, branding);
    # How a pattern is worn only matters when there is one.
    public = (
        versions[0].theme,
        versions[0].logo,
        versions[0].pattern,
        versions[0].pattern_style if versions[0].pattern else ""
    )
        if versions
        else (DEFAULT_THEME.as_dict(), "", "", "");
    if (theme, logo, pattern, style if pattern else "") == public {
        raise Refused(
            "nothing_to_publish", "The storefront already shows this theme and logo."
        );
    }
    return {"ok": True, "version": _publish(scope, theme, logo, pattern, style)};
}

def _rollback_theme(tenant: str, version: int) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, CONFIGURE);
    branding = _branding(scope);
    chosen = [
        v
        for v in _versions(scope, branding)
        if v.version == version
    ];
    if not chosen {
        raise Refused("unknown_version", f"There is no published version {version}.");
    }
    earlier = chosen[0];
    theme = dict(earlier.theme);
    logo = earlier.logo;
    pattern = earlier.pattern;
    style = earlier.pattern_style;
    def _set(b: Branding) {
        b.draft = theme;
        b.draft_logo = logo;
        b.draft_pattern = pattern;
        b.draft_pattern_style = style;
    }
    _edit_draft(scope, _set);
    return {"ok": True, "version": _publish(scope, theme, logo, pattern, style)};
}

def:protect get_branding(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _get_branding(tenant); });  # jac:ignore[W1037]
}

def _do_save_theme(tenant: str, theme: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _save_theme(tenant, theme); });  # jac:ignore[W1037]
}

def _do_upload_logo(
    tenant: str, content_type: str, data_base64: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(
        lambda -> any { return _upload_logo(tenant, content_type, data_base64); }  # jac:ignore[W1037]
    );
}

def _do_suggest_themes(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _suggest_themes(tenant); });  # jac:ignore[W1037]
}

def _do_draw_pattern(tenant: str, theme: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _draw_pattern(tenant, theme); });  # jac:ignore[W1037]
}

def _do_remove_pattern(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _remove_pattern(tenant); });  # jac:ignore[W1037]
}

def _do_set_pattern_style(tenant: str, style: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _set_pattern_style(tenant, style); });  # jac:ignore[W1037]
}

def _do_remove_logo(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _remove_logo(tenant); });  # jac:ignore[W1037]
}

def _do_publish_theme(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _publish_theme(tenant); });  # jac:ignore[W1037]
}

def _do_rollback_theme(tenant: str, version: int) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _rollback_theme(tenant, version); });  # jac:ignore[W1037]
}

def:pub public_branding(slug: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The cinema's published theme, its storefront CSS and logo, for anyone (no login).
    cinema = open_cinema(slug);
    if cinema is None {
        return NOT_FOUND;
    }
    shown = branding_of(cinema);
    # Checked again on the way out, so only token values ever become CSS.
    theme = parse_theme(shown.get("theme") or DEFAULT_THEME.as_dict());
    logo = shown.get("logo", "");
    pattern = shown.get("pattern", "");
    return {
        "ok": True,
        "cinema": {"name": cinema.name, "slug": cinema.slug},
        "branding": {
            "version": shown.get("version", 0),
            "theme": theme.as_dict(),
            "css": theme_css(theme, "storefront"),
            "logo": _data_url(logo),
            "pattern": _data_url(pattern),
            "pattern_style": (shown.get("pattern_style") or DEFAULT_STYLE)
                if pattern
                else ""
        }
    };
}

def:protect save_theme(tenant: str, theme: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "theme.saved",
        "theme",
        "",
        lambda -> any { return _do_save_theme(tenant, theme); }  # jac:ignore[W1037]
    );
}

def:protect upload_logo(
    tenant: str, content_type: str, data_base64: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "theme.logo_uploaded",
        "theme",
        "",
        lambda -> any { return _do_upload_logo(tenant, content_type, data_base64); }  # jac:ignore[W1037]
    );
}

def:protect suggest_themes(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "theme.suggested",
        "theme",
        "",
        lambda -> any { return _do_suggest_themes(tenant); }  # jac:ignore[W1037]
    );
}

def:protect draw_pattern(tenant: str, theme: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "theme.pattern_drawn",
        "theme",
        "",
        lambda -> any { return _do_draw_pattern(tenant, theme); }  # jac:ignore[W1037]
    );
}

def:protect remove_pattern(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "theme.pattern_removed",
        "theme",
        "",
        lambda -> any { return _do_remove_pattern(tenant); }  # jac:ignore[W1037]
    );
}

def:protect set_pattern_style(tenant: str, style: str) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "theme.pattern_styled",
        "theme",
        "",
        lambda -> any { return _do_set_pattern_style(tenant, style); }  # jac:ignore[W1037]
    );
}

def:protect remove_logo(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "theme.logo_removed",
        "theme",
        "",
        lambda -> any { return _do_remove_logo(tenant); }  # jac:ignore[W1037]
    );
}

def:protect publish_theme(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "theme.published",
        "theme",
        "",
        lambda -> any { return _do_publish_theme(tenant); }  # jac:ignore[W1037]
    );
}

def:protect rollback_theme(tenant: str, version: int) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "theme.rolled_back",
        "theme",
        "",
        lambda -> any { return _do_rollback_theme(tenant, version); },
        detail=f"to version {version}"  # jac:ignore[W1037]
    );
}
