"""The snack catalog (P12.1), as tenant nodes (ADR-0004; design guide docs/snacks-guide.md).

Tenant -> SnackCategory, Tenant -> SnackProduct -> SnackVariant, Tenant ->
SnackAddonGroup (P12.3), each owned by the
cinema's principal and attached to its access group like every tenant node. A product
names its category by id. A variant is what customers buy; its id never changes, so
orders, stock and prices can point at it whatever staff rename. Checked by
core/snacks/catalog.jac; changed only by the snacks endpoints.
"""

node SnackCategory {
    # How products are organized for staff and customers. status is "active" or
    # "archived" (kept for history and reports; off the storefront).
    has tenant_id: str,
        name: str,
        position: int = 0,
        status: str = "active",
        created_at: str = "",
        updated_at: str = "";
}

node SnackProduct {
    # A product family (Popcorn, Coca-Cola). kind is "single" or "variants";
    # option_names are the variant axes (["Size"], ["Flavour", "Size"]); status is
    # "draft", "active" or "archived". images are [{"image_id", "key"}], the first the
    # main one, each key a media key. off_at lists the venues that don't sell it
    # (P12.2); a new venue sells it. addon_group_ids are the add-on groups customers
    # choose from (P12.3). A combo's components are {"label", "quantity", "kind"
    # ("fixed" or "choice"), "variant_ids"} (P12.3).
    has tenant_id: str,
        name: str,
        category_id: str = "",
        brand: str = "",
        description: str = "",
        tags: list[str] = [],
        purpose: str = "",
        kind: str = "single",
        option_names: list[str] = [],
        status: str = "draft",
        images: list[dict[str, str]] = [],
        off_at: list[str] = [],
        addon_group_ids: list[str] = [],
        components: list[dict[str, any]] = [],  # jac:ignore[W1037]
        created_at: str = "",
        updated_at: str = "",
        published_at: str = "";
}

node GlassesConfig {
    # Per-venue switch for the dedicated tracked snack product used by 3D checkout.
    has tenant_id: str,
        venue_id: str,
        product_id: str,
        variant_id: str,
        sold: bool = False,
        updated_at: str = "";
}

node SnackVariant {
    # A sellable version of a product (Medium; Zero Sugar · 500 ml). option_values
    # line up with the product's option_names; sku is unique in the cinema (a claim,
    # ADR-0007) or "" in a draft; price_cents is None until set. off_at lists the venues
    # where it isn't available; venue_prices are venues' own prices (P12.2).
    # stock_rules are per venue: {"low": threshold, "at_zero": "unavailable" or
    # "allow"} (P12.4); its counts live in core/claims.jac (snacks.inventory_api).
    has tenant_id: str,
        product_id: str,
        option_values: list[str] = [],
        sku: str = "",
        barcode: str = "",
        price_cents: int | None = None,
        available: bool = True,
        track_stock: bool = False,
        off_at: list[str] = [],
        venue_prices: dict[str, int] = {},
        stock_rules: dict[str, dict[str, any]] = {},  # jac:ignore[W1037]
        position: int = 0,
        created_at: str = "",
        updated_at: str = "";
}

node SnackAddonGroup {
    # Extras customers add to a product (P12.3; design guide §5A), shared by the
    # products it's attached to. name is for staff ("Popcorn extras"), label is what
    # customers see ("Choose your extras"); they pick min_picks to max_picks, the same
    # option more than once when repeatable. Each option is {"option_id", "name",
    # "price_cents", "off_at": [venue ids]}.
    has tenant_id: str,
        name: str,
        label: str,
        min_picks: int = 0,
        max_picks: int = 1,
        repeatable: bool = False,
        options: list[dict[str, any]] = [],  # jac:ignore[W1037]
        created_at: str = "",
        updated_at: str = "";
}

node StockMovement {
    # One change to a variant's stock at a venue (P12.4; design guide §8C): the reason
    # ("received", "damaged", "count", "other", or "sale" for an order), the change to
    # on hand, on hand after it, a note, who made it (a staff root id, "" for a sale) and
    # when. Movements are only ever added.
    has tenant_id: str,
        product_id: str,
        variant_id: str,
        venue_id: str,
        reason: str,
        change: int,
        on_hand_after: int,
        note: str = "",
        made_by: str = "",
        at: str = "";
}
