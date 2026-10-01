"""A cinema's home page (P4.1b): Tenant -> HomePage -> HomePageVersion.

Owned by the cinema's principal (ADR-0003) and granted to its access group (ADR-0004),
like every tenant node. Pages are stored as parse_page-checked data (page.jac), with
movies named by id; the storefront's copy names them by public key.
"""

node HomePage {
    # The cinema's one HomePage, made on first save and recorded on
    # Tenant.home_page_id. draft is what the owner is editing ({} means the default
    # page). version is the latest published version's number: publishing raises it,
    # so concurrent publishes write the same record and the database re-runs all but
    # one (JI-031).
    has tenant_id: str,
        draft: dict[str, any] = {},  # jac:ignore[W1037]
        version: int = 0,
        # Photos uploaded for the page (names in the cinema's media folder, newest
        # last); the About section shows some of them.
        photos: list[str] = [],
        updated_at: str = "";
}

node HomePageVersion {
    # One published page. Never changed: rolling back publishes a copy.
    has tenant_id: str,
        version: int,
        page: dict[str, any] = {},  # jac:ignore[W1037]
        published_at: str = "";
}
