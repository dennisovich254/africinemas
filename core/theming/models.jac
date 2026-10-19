"""A cinema's branding (P3.8a): Tenant -> Branding -> ThemeVersion.

Owned by the cinema's principal (ADR-0003) and granted to its access group (ADR-0004),
like every tenant node. Themes are stored as parse_theme-checked data (branding.jac).
"""

node Branding {
    # The cinema's one Branding, made on first use and recorded on Tenant.branding_id.
    # The draft is what the owner is editing ({} means the platform default theme), with
    # its logo as base64 WebP ("" for none). version is the latest published version's
    # number: publishing raises it, so concurrent publishes write the same record and
    # the database re-runs all but one (JI-031).
    has tenant_id: str,
        draft: dict[str, any] = {},  # jac:ignore[W1037]
        draft_logo: str = "",
        version: int = 0,
        updated_at: str = "",
        # Theme suggestions asked for on suggest_day (ISO date): they cost a model call,
        # so a cinema gets SUGGEST_DAILY a day (ADR-0043).
        suggest_day: str = "",
        suggest_count: int = 0,
        # The pattern drawn from the logo (ADR-0045): base64 WebP ("" for none), how the
        # storefront wears it (a pattern style), and drawings asked for on pattern_day.
        draft_pattern: str = "",
        draft_pattern_style: str = "",
        pattern_day: str = "",
        pattern_count: int = 0;
}

node ThemeVersion {
    # One published theme and logo. Never changed: rolling back publishes a copy.
    has tenant_id: str,
        version: int,
        theme: dict[str, any] = {},  # jac:ignore[W1037]
        logo: str = "",
        pattern: str = "",
        pattern_style: str = "",
        published_at: str = "";
}
