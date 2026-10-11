"""The snack catalog's CSV import and export (P12.5), as pure logic. Design guide §4C.

read_csv reads the file (at most ROWS_MAX rows); guess_mapping finds each field's
column by its usual names (staff can change the mapping); plan_import turns rows into
products and variants and reports every problem with its row number (the header is row
1) before anything is saved. Rows with the same product name (ignoring case) are one
product: one variant per row, named by its variant value under one option (Size unless
an option column says), or a single item when the row has no variant. A product that
already exists (same name) is updated, its variants matched by SKU; new SKUs are added;
nothing is removed. export_csv writes the same columns.

The format is AfriCinemas' own (no industry schema): product_name, category, brand,
option, variant, sku, price (in shillings), currency (KES or empty).
"""

import csv;
import io;
import re;

glob FIELDS: list[str] = [
         "product_name",
         "category",
         "brand",
         "option",
         "variant",
         "sku",
         "price",
         "currency"
     ],
     REQUIRED: list[str] = ["product_name", "category", "sku", "price"],
     ALIASES: dict[str, list[str]] = {
         "product_name": ["product_name", "product", "name", "product name"],
         "category": ["category", "category_name"],
         "brand": ["brand"],
         "option": ["option", "option_name"],
         "variant": ["variant", "size", "variant_name", "value"],
         "sku": ["sku", "code", "product_code"],
         "price": ["price", "selling_price", "price_kes"],
         "currency": ["currency"]
     },
     ROWS_MAX: int = 2000,
     SKU_PATTERN: str = r"[A-Z0-9][A-Z0-9._-]{0,31}",
     PRICE_MAX_CENTS: int = 10000000;

obj ExistingProduct {
    # What the cinema already has, for matching: a product by name, its variants by SKU.
    has product_id: str,
        name: str,
        category: str,
        kind: str,
        option_names: list[str],
        variants: list[dict[str, any]];  # jac:ignore[W1037]
}

def read_csv(text: str) -> tuple[list[str], list[dict[str, str]]] {
    # The header and the rows (each {column: value}), at most ROWS_MAX rows.
    reader = csv.DictReader(io.StringIO(text.lstrip("﻿")));
    headers = [h.strip() for h in (reader.fieldnames or [])];
    rows: list[dict[str, str]] = [];
    for raw in reader {
        if len(rows) >= ROWS_MAX {
            break;
        }
        row = {
            (k or "").strip(): (v or "").strip()
            for (k, v) in raw.items()
            if k is not None
        };
        if any(row.values()) {
            rows.append(row);
        }
    }
    return (headers, rows);
}

def guess_mapping(headers: list[str]) -> dict[str, str] {
    # Each field's column by its usual names, or "" when there's none.
    folded = {h.strip().lower(): h for h in headers};
    return {
        field: (
            [
                folded[a]
                for a in ALIASES[field]
                if a in folded
            ]
            + [""]
        )[0] for field in FIELDS
    };
}

def price_cents_of(text: str) -> int | None {
    # "1,250", "150.00" -> cents; None unless whole shillings from 1 to 100,000.
    cleaned = text.replace(",", "").strip();
    found = re.fullmatch(r"([0-9]{1,6})(\.0{1,2})?", cleaned);
    if found is None {
        return None;
    }
    cents = int(found.group(1)) * 100;
    return cents if 100 <= cents <= PRICE_MAX_CENTS else None;
}

def _error(row: int, field: str, message: str) -> dict[str, any] {  # jac:ignore[W1037]
    return {"row": row, "field": field, "message": message};
}

def plan_import(
    rows: list[dict[str, str]],
    mapping: dict[str, str],
    existing: list[ExistingProduct],
    categories: list[str],
    create_categories: bool
) -> tuple[list[dict[str, any]], list[dict[str, any]]] {  # jac:ignore[W1037]
    # The products to create or update, or [] and every problem by row.
    errors: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for field in REQUIRED {
        if not mapping.get(field) {
            errors.append(
                _error(1, field, f"Choose the column for {field.replace('_', ' ')}.")
            );
        }
    }
    if errors {
        return ([], errors);
    }
    known_categories = {c.casefold(): c for c in categories};
    by_name = {p.name.casefold(): p for p in existing};
    sku_owner: dict[str, tuple[str, str]] = {};
    for p in existing {
        for v in p.variants {
            sku_owner[str(v["sku"]).upper()] = (p.name, str(v["variant_id"]));
        }
    }
    groups: dict[str, list[tuple[int, dict[str, str]]]] = {};
    order: list[str] = [];
    seen_skus: dict[str, int] = {};
    def cell(row: dict[str, str], field: str) -> str {
        column = mapping.get(field, "");
        return " ".join(row.get(column, "").split()) if column else "";
    }
    for (i, row) in enumerate(rows) {
        line = i + 2;
        name = cell(row, "product_name");
        if not name or len(name) > 80 {
            errors.append(
                _error(
                    line,
                    "product_name",
                    "Enter the product's name (up to 80 characters)."
                )
            );
        }
        category = cell(row, "category");
        if not category {
            errors.append(_error(line, "category", "Enter the product's category."));
        } elif category.casefold() not in known_categories and not create_categories {
            errors.append(
                _error(
                    line,
                    "category",
                    f"There's no category called '{category}'. Add it first, or tick 'Make missing categories'."
                )
            );
        }
        sku = cell(row, "sku").upper();
        if not sku {
            errors.append(_error(line, "sku", "Enter a SKU."));
        } elif re.fullmatch(SKU_PATTERN, sku) is None {
            errors.append(
                _error(
                    line,
                    "sku",
                    f"{sku}: use up to 32 letters, digits, dots, dashes or underscores."
                )
            );
        } elif sku in seen_skus {
            errors.append(
                _error(line, "sku", f"{sku} is also on row {seen_skus[sku]}.")
            );
        } elif sku in sku_owner and sku_owner[sku][0].casefold() != name.casefold() {
            errors.append(
                _error(line, "sku", f"{sku} is already used by {sku_owner[sku][0]}.")
            );
        }
        if sku and sku not in seen_skus {
            seen_skus[sku] = line;
        }
        if price_cents_of(cell(row, "price")) is None {
            errors.append(
                _error(
                    line,
                    "price",
                    "Enter the price in whole shillings, from 1 to 100,000."
                )
            );
        }
        currency = cell(row, "currency").upper();
        if currency and currency != "KES" {
            errors.append(
                _error(
                    line,
                    "currency",
                    "Prices are in KES; leave the currency empty or write KES."
                )
            );
        }
        if name {
            key = name.casefold();
            if key not in groups {
                groups[key] = [];
                order.append(key);
            }
            groups[key].append((line, row));
        }
    }
    plan: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for key in order {
        lines = groups[key];
        first = lines[0][1];
        name = cell(first, "product_name");
        category = cell(first, "category");
        option = cell(first, "option") or "Size";
        has_variants = any(cell(r, "variant") for (_, r) in lines);
        for (line, r) in lines[1:] {
            if cell(r, "category").casefold() != category.casefold() {
                errors.append(
                    _error(
                        line,
                        "category",
                        f"{name} is in {category} on row {lines[0][
                            0
                        ]}; use one category per product."
                    )
                );
            }
        }
        if not has_variants and len(lines) > 1 {
            for (line, _) in lines[1:] {
                errors.append(
                    _error(
                        line,
                        "variant",
                        f"{name} has no variants, so it can only be on one row. Give each row a variant, like Small or 500 ml."
                    )
                );
            }
        }
        if has_variants {
            for (line, r) in lines {
                if not cell(r, "variant") {
                    errors.append(
                        _error(
                            line,
                            "variant",
                            f"{name} has variants on other rows; give this row one too."
                        )
                    );
                }
            }
        }
        found = by_name.get(key);
        shape_kind = "variants" if has_variants else "single";
        if found is not None
            and (
                found.kind != shape_kind
                or (has_variants and found.option_names != [option])
            ) {
            errors.append(
                _error(
                    lines[0][0],
                    "variant",
                    f"{name} is already in your catalog as {'a single item'
                        if found.kind == 'single'
                        else 'a product with '
                            + ', '.join(
                                found.option_names
                            )}; match it, or change it in the product editor first."
                )
            );
        }
        known = {str(v["sku"]).upper(): str(v["variant_id"]) for v in found.variants}
            if found is not None
            else {};
        variants: list[dict[str, any]] = [];  # jac:ignore[W1037]
        for (_, r) in lines {
            sku = cell(r, "sku").upper();
            variants.append(
                {
                    "variant_id": known.get(sku, ""),
                    "option_values": [cell(r, "variant")] if has_variants else [],
                    "sku": sku,
                    "price_cents": price_cents_of(cell(r, "price")),
                    "action": "update" if sku in known else "create"
                }
            );
        }
        plan.append(
            {
                "name": name,
                "category": known_categories.get(category.casefold(), category),
                "new_category": category.casefold() not in known_categories,
                "brand": cell(first, "brand"),
                "kind": "variants" if has_variants else "single",
                "option_names": [option] if has_variants else [],
                "action": "update" if found is not None else "create",
                "product_id": found.product_id if found is not None else "",
                "variants": variants
            }
        );
    }
    if errors {
        return (
            [],
            sorted(
                errors,
                key=lambda (e: dict[str, any]) -> tuple[int, str] { return (
                    e["row"],
                    e["field"]
                ); }
            )
        );  # jac:ignore[W1037]
    }
    return (plan, []);
}

def _shillings(cents: int | None) -> str {
    if cents is None {
        return "";
    }
    return str(cents // 100)
        if cents % 100 == 0
        else f"{cents // 100}.{cents % 100:02d}";
}

def export_csv(products: list[dict[str, any]]) -> str {  # jac:ignore[W1037]
    # The catalog in the import's columns: one row per variant.
    out = io.StringIO();
    writer = csv.writer(out, lineterminator="\n");
    writer.writerow(FIELDS);
    for p in products {
        options: list[str] = p["option_names"];
        for v in p["variants"] {
            values: list[str] = v["option_values"];
            writer.writerow(
                [
                    p["name"],
                    p["category"],
                    p["brand"],
                    " / ".join(options),
                    " / ".join(values),
                    v["sku"],
                    _shillings(v["price_cents"]),
                    "KES"
                ]
            );
        }
    }
    return out.getvalue();
}
