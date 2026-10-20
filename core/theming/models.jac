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
        # The pattern drawn from the logo (ADR-0045), replaced by the brand kit (ADR-0046).
        # No longer read or written; kept so Branding nodes saved with them still load.
        draft_pattern: str = "",
        draft_pattern_style: str = "",
        pattern_day: str = "",
        pattern_count: int = 0,
        # The brand kit drawn from the logo (ADR-0046): {"motifs": [{"name", "mask"}],
        # "look": {...}} or {} for none, and kits drawn on kit_day (KIT_DAILY).
        draft_kit: dict[str, any] = {},  # jac:ignore[W1037]
        kit_day: str = "",
        kit_count: int = 0,
        # The storefront the AI wrote (ADR-0048): {"html", "css", "model"} or {} for none.
        draft_page: dict[str, str] = {};
}

node ThemeVersion {
    # One published theme and logo. Never changed: rolling back publishes a copy.
    has tenant_id: str,
        version: int,
        theme: dict[str, any] = {},  # jac:ignore[W1037]
        logo: str = "",
        # pattern and pattern_style: ADR-0045, no longer used; kept so saved versions load.
        pattern: str = "",
        pattern_style: str = "",
        kit: dict[str, any] = {},  # jac:ignore[W1037]
        page: dict[str, str] = {},
        published_at: str = "";
}
