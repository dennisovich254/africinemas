"""Checking the snack catalog (P12.1), as pure logic (design guide: docs/snacks-guide.md).

- check_category_name: 1 to CATEGORY_NAME_MAX characters.
- check_product: a name (1 to NAME_MAX), an optional brand (BRAND_MAX), description
  (DESCRIPTION_MAX) and tags (up to TAGS_MAX, each 1 to TAG_MAX, kept once ignoring
  case), a type in KINDS, and option names: none for a single product, 1 to
  OPTIONS_MAX (each 1 to OPTION_NAME_MAX, unique ignoring case) for one with variants.
- check_variants: a single product has exactly one variant, with no option values; a
  product with variants has 1 to VARIANTS_MAX, each with one value (1 to
  OPTION_VALUE_MAX) per option name and no two the same. A SKU (SKU_PATTERN, kept in
  capitals) is unique within the product; a barcode is 8 to 14 digits; a price is whole
  cents from PRICE_MIN_CENTS to PRICE_MAX_CENTS. A draft may leave the SKU and the price
  empty. A row keeps the id it came with; new rows get one from the endpoint.
- publish_problems: what stops a checked product from being sold.

Spaces are tidied. Every problem is reported at once, as {field, code, message}, the
field naming the row ("variants[1].price_cents") and the message the variant.
"""

import re;

glob CATEGORY_NAME_MAX: int = 40,
     NAME_MAX: int = 80,
     BRAND_MAX: int = 40,
     DESCRIPTION_MAX: int = 500,
     TAGS_MAX: int = 10,
     TAG_MAX: int = 24,
     KINDS: list[str] = ["single", "variants"],
     OPTIONS_MAX: int = 2,
     OPTION_NAME_MAX: int = 20,
     OPTION_VALUE_MAX: int = 30,
     VARIANTS_MAX: int = 50,
     SKU_PATTERN: str = r"[A-Z0-9][A-Z0-9._-]{0,31}",
     BARCODE_PATTERN: str = r"[0-9]{8,14}",
     ID_PATTERN: str = r"[a-z0-9-]{8,40}",
     PRICE_MIN_CENTS: int = 100,  # KES 1
     PRICE_MAX_CENTS: int = 10000000;  # KES 100,000

obj ProductFields {
    has name: str,
        brand: str,
        description: str,
        tags: list[str],
        kind: str,
        option_names: list[str];
}

obj VariantFields {
    has variant_id: str,
        option_values: list[str],
        sku: str,
        barcode: str,
        price_cents: int | None,
        available: bool,
        track_stock: bool;
}

def _tidy(text: any) -> str {  # jac:ignore[W1037]
    return " ".join(text.split()) if isinstance(text, str) else "";
}

def _as_int(value: any) -> int | None {  # jac:ignore[W1037]
    # `value` if it's a whole number (not a bool), else None.
    return value if isinstance(value, int) and not isinstance(value, bool) else None;
}

def _as_list(value: any) -> list[any] {  # jac:ignore[W1037]
    return value if isinstance(value, list) else [];
}

def _problem(field: str, code: str, message: str) -> dict[str, str] {
    return {"field": field, "code": code, "message": message};
}

def sku_key(sku: any) -> str {  # jac:ignore[W1037]
    # A SKU as kept and compared: trimmed, in capitals.
    return sku.strip().upper() if isinstance(sku, str) else "";
}

def variant_label(option_values: list[str]) -> str {
    # How staff and customers name a variant: "Medium", "Zero Sugar · 500 ml".
    return " · ".join(option_values) if option_values else "Default";
}

def check_category_name(name: any) -> tuple[str | None, list[dict[str, str]]] {  # jac:ignore[W1037]
    clean = _tidy(name);
    if not clean or len(clean) > CATEGORY_NAME_MAX {
        return (
            None,
            [
                _problem(
                    "name",
                    "NAME_INVALID",
                    f"Enter a name of 1 to {CATEGORY_NAME_MAX} characters."
                )
            ]
        );
    }
    return (clean, []);
}

def check_product(
    name: any,  # jac:ignore[W1037]
    brand: any,  # jac:ignore[W1037]
    description: any,  # jac:ignore[W1037]
    tags: any,  # jac:ignore[W1037]
    kind: any,  # jac:ignore[W1037]
    option_names: any  # jac:ignore[W1037]
) -> tuple[ProductFields | None, list[dict[str, str]]] {
    problems: list[dict[str, str]] = [];
    clean_name = _tidy(name);
    if not clean_name or len(clean_name) > NAME_MAX {
        problems.append(
            _problem(
                "name", "NAME_INVALID", f"Enter a name of 1 to {NAME_MAX} characters."
            )
        );
    }
    clean_brand = _tidy(brand);
    if len(clean_brand) > BRAND_MAX {
        problems.append(
            _problem(
                "brand", "BRAND_TOO_LONG", f"Keep the brand to {BRAND_MAX} characters."
            )
        );
    }
    clean_description = _tidy(description);
    if len(clean_description) > DESCRIPTION_MAX {
        problems.append(
            _problem(
                "description",
                "DESCRIPTION_TOO_LONG",
                f"Keep the description to {DESCRIPTION_MAX} characters."
            )
        );
    }
    given_tags: list[any] = tags if isinstance(tags, list) else [];  # jac:ignore[W1037]
    clean_tags: list[str] = [];
    for t in given_tags {
        tag = _tidy(t);
        if tag and tag.casefold() not in [x.casefold() for x in clean_tags] {
            clean_tags.append(tag);
        }
    }
    if len(clean_tags) > TAGS_MAX or any(len(t) > TAG_MAX for t in clean_tags) {
        problems.append(
            _problem(
                "tags",
                "TAGS_INVALID",
                f"Use up to {TAGS_MAX} tags of up to {TAG_MAX} characters each."
            )
        );
    }
    clean_kind = kind if isinstance(kind, str) and kind in KINDS else "";
    if not clean_kind {
        problems.append(
            _problem(
                "kind", "KIND_INVALID", "Choose a single item or one with variants."
            )
        );
    }
    given_options: list[any] = option_names if isinstance(option_names, list) else [];  # jac:ignore[W1037]
    clean_options = [_tidy(o) for o in given_options];
    folded = [o.casefold() for o in clean_options];
    if clean_kind == "single" and clean_options {
        problems.append(
            _problem(
                "option_names",
                "OPTIONS_NOT_ALLOWED",
                "A single item has no options. Choose 'has variants' to add sizes."
            )
        );
    } elif clean_kind == "variants"
        and (
            not clean_options
            or len(clean_options) > OPTIONS_MAX
            or any(not o or len(o) > OPTION_NAME_MAX for o in clean_options)
            or len(set(folded)) != len(folded)
        ) {
        problems.append(
            _problem(
                "option_names",
                "OPTIONS_INVALID",
                f"Name 1 or {OPTIONS_MAX} different options, like Size or Flavour."
            )
        );
    }
    if problems {
        return (None, problems);
    }
    return (
        ProductFields(
            name=clean_name,
            brand=clean_brand,
            description=clean_description,
            tags=clean_tags,
            kind=clean_kind,
            option_names=clean_options
        ),
        []
    );
}

def check_variants(
    kind: str,
    option_names: list[str],
    rows: any  # jac:ignore[W1037]
) -> tuple[list[VariantFields] | None, list[dict[str, str]]] {
    problems: list[dict[str, str]] = [];
    given: list[any] = rows if isinstance(rows, list) else [];  # jac:ignore[W1037]
    if kind == "single" and len(given) != 1 {
        problems.append(
            _problem("variants", "ONE_VARIANT", "A single item is sold in one version.")
        );
    } elif kind != "single" and (not given or len(given) > VARIANTS_MAX) {
        problems.append(
            _problem("variants", "VARIANTS_COUNT", f"Add 1 to {VARIANTS_MAX} variants.")
        );
    }
    kept: list[VariantFields] = [];
    seen_values: list[str] = [];
    seen_skus: list[str] = [];
    for (i, raw) in enumerate(
        given[:1] if kind == "single" else given[:VARIANTS_MAX]
    ) {
        row: dict[str, any] = raw if isinstance(raw, dict) else {};  # jac:ignore[W1037]
        at = f"variants[{i}]";
        raw_values = _as_list(row.get("option_values"));
        values = [_tidy(v) for v in raw_values];
        label = variant_label(values);
        wanted = len(option_names) if kind != "single" else 0;
        values_key = "|".join([v.casefold() for v in values]);
        if len(values) != wanted
            or any(not v or len(v) > OPTION_VALUE_MAX for v in values) {
            problems.append(
                _problem(
                    f"{at}.option_values",
                    "VALUES_INVALID",
                    "Give this variant no option values."
                        if wanted == 0
                        else f"Give this variant a value of 1 to {OPTION_VALUE_MAX} characters for each of: {', '.join(
                            option_names
                        )}."
                )
            );
        } elif values_key in seen_values {
            problems.append(
                _problem(
                    f"{at}.option_values",
                    "VARIANT_DUPLICATE",
                    f"{label} is already a variant."
                )
            );
        }
        seen_values.append(values_key);
        sku = sku_key(row.get("sku"));
        if sku and re.fullmatch(SKU_PATTERN, sku) is None {
            problems.append(
                _problem(
                    f"{at}.sku",
                    "SKU_INVALID",
                    f"{label}: use up to 32 letters, digits, dots, dashes or underscores."
                )
            );
        } elif sku and sku in seen_skus {
            problems.append(
                _problem(f"{at}.sku", "SKU_DUPLICATE", f"{label}: {sku} is used above.")
            );
        }
        if sku {
            seen_skus.append(sku);
        }
        barcode = _tidy(row.get("barcode")).replace(" ", "");
        if barcode and re.fullmatch(BARCODE_PATTERN, barcode) is None {
            problems.append(
                _problem(
                    f"{at}.barcode",
                    "BARCODE_INVALID",
                    f"{label}: a barcode is 8 to 14 digits."
                )
            );
        }
        raw_price = row.get("price_cents");
        price = _as_int(raw_price);
        if raw_price is not None
            and (price is None or price < PRICE_MIN_CENTS or price > PRICE_MAX_CENTS) {
            problems.append(
                _problem(
                    f"{at}.price_cents",
                    "PRICE_INVALID",
                    f"{label}: enter a price from KES 1 to KES 100,000."
                )
            );
            price = None;
        }
        given_id = row.get("variant_id");
        variant_id = given_id
            if isinstance(given_id, str) and re.fullmatch(ID_PATTERN, given_id)
            else "";
        kept.append(
            VariantFields(
                variant_id=variant_id,
                option_values=values,
                sku=sku,
                barcode=barcode,
                price_cents=price,
                available=bool(row.get("available", True)),
                track_stock=bool(row.get("track_stock", False))
            )
        );
    }
    if problems {
        return (None, problems);
    }
    return (kept, []);
}

def publish_problems(
    category_ok: bool, variants: list[VariantFields]
) -> list[dict[str, str]] {
    # What stops a checked product from being sold: no category, no variants, a variant
    # without a price or SKU, or none available.
    problems: list[dict[str, str]] = [];
    if not category_ok {
        problems.append(
            _problem(
                "category_id",
                "CATEGORY_REQUIRED",
                "Select a category before publishing."
            )
        );
    }
    if not variants {
        problems.append(
            _problem("variants", "VARIANT_REQUIRED", "Add a variant before publishing.")
        );
    }
    for (i, v) in enumerate(variants) {
        label = variant_label(v.option_values);
        if v.price_cents is None {
            problems.append(
                _problem(
                    f"variants[{i}].price_cents",
                    "PRICE_REQUIRED",
                    f"Enter a selling price for {label}."
                )
            );
        }
        if not v.sku {
            problems.append(
                _problem(
                    f"variants[{i}].sku", "SKU_REQUIRED", f"Enter a SKU for {label}."
                )
            );
        }
    }
    if variants and not any(v.available for v in variants) {
        problems.append(
            _problem(
                "variants",
                "NONE_AVAILABLE",
                "Make at least one variant available to sell."
            )
        );
    }
    return problems;
}
