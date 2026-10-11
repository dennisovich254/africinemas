"""Shared pieces of the snack catalog pages (P12.1): wording, the editor's variant rows, and
the Snacks sub-navigation (Products, Categories).

- snack_path: where each snack page lives (/app/<slug>/snacks[/categories|/new|/<id>]).
- problem_id: the element id a server problem's field shows under
  ("variants[1].sku" -> "p-variants-1-sku").
- generate_rows: the variant rows for the option values typed ("Small, Medium, Large"),
  keeping the rows (and their ids, SKUs and prices) that already match, adding the
  missing combinations, and never removing a row by itself.
- price_text / price_cents_of: a price as staff type it ("300", "1,250") and back.
"""

import from ..shell.AppLink { AppLink }
import from .PricesSection { shillings, cents_of }

glob STATUS_LABELS: dict[str, str] = {
         "draft": "Draft",
         "active": "Active",
         "archived": "Archived"
     },
     SUBNAV: list[tuple[str, str]] = [
         ("", "Products"),
         ("categories", "Categories"),
         ("extras", "Combos & Add-ons"),
         ("stock", "Stock")
     ];

def:pub snack_path(slug: str, rest: str = "") -> str {
    return f"/app/{slug}/snacks/{rest}" if rest else f"/app/{slug}/snacks";
}

def:pub status_label(status: str) -> str {
    return STATUS_LABELS.get(status, status);
}

def:pub problem_id(field: str) -> str {
    return "p-" + field.replace("[", "-").replace("]", "").replace(".", "-");
}

def:pub price_text(cents: any) -> str {  # jac:ignore[W1037]
    return shillings(cents) if cents is not None else "";
}

def:pub price_cents_of(text: str) -> any {  # jac:ignore[W1037]
    # None for an empty price (a draft may leave it), -1 when it can't be read.
    if not text.strip() {
        return None;
    }
    cents = cents_of(text, False);
    return cents if cents is not None and cents > 0 else -1;
}

def:pub split_values(text: str) -> list[str] {
    # "Small, Medium ,Large" -> ["Small", "Medium", "Large"], each once.
    out: list[str] = [];
    for part in text.split(",") {
        value = " ".join(part.split());
        if value and value.lower() not in [x.lower() for x in out] {
            out.append(value);
        }
    }
    return out;
}

def:pub blank_row(values: list[str]) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "variant_id": "",
        "option_values": values,
        "sku": "",
        "barcode": "",
        "price": "",
        "available": True,
        "track_stock": False
    };
}

def:pub generate_rows(
    values_per_option: list[list[str]],
    rows: list[dict[str, any]]  # jac:ignore[W1037]
) -> list[dict[str, any]] {  # jac:ignore[W1037]
    # Every combination of the values, in order, after the rows already there; a
    # combination that already has a row isn't added again.
    combos: list[list[str]] = [[]];
    for values in values_per_option {
        combos = [c + [v] for c in combos for v in values];
    }
    have = ["|".join([x.lower() for x in r["option_values"]]) for r in rows];
    out = list(rows);
    for c in combos {
        if c and "|".join([x.lower() for x in c]) not in have {
            out.append(blank_row(c));
        }
    }
    return out;
}

def:pub SnackSubnav(slug: str, current: str) -> JsxElement {
    return
        <nav aria-label="Snacks" className="flex gap-1 border-b">
            {[
                <AppLink
                    key={key}
                    to={snack_path(slug, key)}
                    current={current == key}
                    className={"inline-flex min-h-11 items-center border-b-2 px-4 text-sm "
                        + (
                            "border-primary font-semibold"
                                if current == key
                                else "border-transparent text-muted-foreground hover:text-foreground"
                        )}
                >
                    {label}
                </AppLink> for (key, label) in SUBNAV
            ]}
        </nav>;
}
