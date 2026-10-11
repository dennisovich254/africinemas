"""The snack catalog (P12.1), as tenant nodes (ADR-0004; design guide docs/snacks-guide.md).

Tenant -> SnackCategory, Tenant -> SnackProduct -> SnackVariant, each owned by the
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
    # main one, each key a media key.
    has tenant_id: str,
        name: str,
        category_id: str = "",
        brand: str = "",
        description: str = "",
        tags: list[str] = [],
        kind: str = "single",
        option_names: list[str] = [],
        status: str = "draft",
        images: list[dict[str, str]] = [],
        created_at: str = "",
        updated_at: str = "",
        published_at: str = "";
}

node SnackVariant {
    # A sellable version of a product (Medium; Zero Sugar · 500 ml). option_values
    # line up with the product's option_names; sku is unique in the cinema (a claim,
    # ADR-0007) or "" in a draft; price_cents is None until set.
    has tenant_id: str,
        product_id: str,
        option_values: list[str] = [],
        sku: str = "",
        barcode: str = "",
        price_cents: int | None = None,
        available: bool = True,
        track_stock: bool = False,
        position: int = 0,
        created_at: str = "",
        updated_at: str = "";
}
