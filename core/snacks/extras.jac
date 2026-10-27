"""Add-on groups and combos (P12.3), as pure logic. Design guide docs/snacks-guide.md §5.

- check_addon_group: an internal name (1 to GROUP_NAME_MAX), what customers see (1 to
  GROUP_LABEL_MAX), pick limits (0 <= min <= max, max >= 1, max <= the options unless
  an option may be picked more than once: repeatable), and 1 to ADDON_OPTIONS_MAX
  options, each a name (1 to OPTION_NAME_MAX, unique ignoring case) and an extra price
  in whole cents from 0 to PRICE_MAX_CENTS. An option keeps the id it came with.
- check_components: a combo's 1 to COMPONENTS_MAX components, each a label (1 to
  COMPONENT_LABEL_MAX), a quantity (1 to QUANTITY_MAX) and either one fixed variant or a
  choice of 2 to CHOICES_MAX eligible variants, none repeated.
- combo_on_sale: a combo can be sold only where every component can be filled.

Every problem is reported at once, as {field, code, message}.
"""

import re;
import from core.money { whole_shillings }

glob GROUP_NAME_MAX: int = 40,
     GROUP_LABEL_MAX: int = 60,
     OPTION_NAME_MAX: int = 40,
     ADDON_OPTIONS_MAX: int = 20,
     COMPONENTS_MAX: int = 6,
     COMPONENT_LABEL_MAX: int = 40,
     QUANTITY_MAX: int = 10,
     CHOICES_MAX: int = 30,
     PRICE_MAX_CENTS: int = 10000000,  # KES 100,000
     ID_PATTERN: str = r"[a-z0-9-]{8,40}";

obj AddonOptionFields {
    has option_id: str,
        name: str,
        price_cents: int;
}

obj AddonGroupFields {
    has name: str,
        label: str,
        min_picks: int,
        max_picks: int,
        repeatable: bool,
        options: list[AddonOptionFields];
}

obj ComponentFields {
    has label: str,
        quantity: int,
        kind: str,
        variant_ids: list[str];
}

def _tidy(text: any) -> str {  # jac:ignore[W1037]
    return " ".join(text.split()) if isinstance(text, str) else "";
}

def _as_int(value: any) -> int | None {  # jac:ignore[W1037]
    return value if isinstance(value, int) and not isinstance(value, bool) else None;
}

def _as_list(value: any) -> list[any] {  # jac:ignore[W1037]
    return value if isinstance(value, list) else [];
}

def _as_dict(value: any) -> dict[str, any] {  # jac:ignore[W1037]
    return value if isinstance(value, dict) else {};
}

def _problem(field: str, code: str, message: str) -> dict[str, str] {
    return {"field": field, "code": code, "message": message};
}

def check_addon_group(
    name: any,  # jac:ignore[W1037]
    label: any,  # jac:ignore[W1037]
    min_picks: any,  # jac:ignore[W1037]
    max_picks: any,  # jac:ignore[W1037]
    repeatable: any,  # jac:ignore[W1037]
    options: any  # jac:ignore[W1037]
) -> tuple[AddonGroupFields | None, list[dict[str, str]]] {
    problems: list[dict[str, str]] = [];
    clean_name = _tidy(name);
    if not clean_name or len(clean_name) > GROUP_NAME_MAX {
        problems.append(
            _problem(
                "name",
                "NAME_INVALID",
                f"Enter a name of 1 to {GROUP_NAME_MAX} characters."
            )
        );
    }
    clean_label = _tidy(label);
    if not clean_label or len(clean_label) > GROUP_LABEL_MAX {
        problems.append(
            _problem(
                "label",
                "LABEL_INVALID",
                f"Enter what customers see, 1 to {GROUP_LABEL_MAX} characters."
            )
        );
    }
    given = _as_list(options);
    if not given or len(given) > ADDON_OPTIONS_MAX {
        problems.append(
            _problem(
                "options", "OPTIONS_COUNT", f"Add 1 to {ADDON_OPTIONS_MAX} add-ons."
            )
        );
    }
    kept: list[AddonOptionFields] = [];
    seen: list[str] = [];
    for (i, raw) in enumerate(given[:ADDON_OPTIONS_MAX]) {
        row = _as_dict(raw);
        option_name = _tidy(row.get("name"));
        if not option_name or len(option_name) > OPTION_NAME_MAX {
            problems.append(
                _problem(
                    f"options[{i}].name",
                    "NAME_INVALID",
                    f"Enter a name of 1 to {OPTION_NAME_MAX} characters."
                )
            );
        } elif option_name.casefold() in seen {
            problems.append(
                _problem(
                    f"options[{i}].name",
                    "OPTION_DUPLICATE",
                    f"'{option_name}' is already in the group."
                )
            );
        }
        seen.append(option_name.casefold());
        given_price = _as_int(row.get("price_cents"));
        price = given_price if given_price is not None else 0;
        if given_price is None
            or price < 0
            or price > PRICE_MAX_CENTS
            or not whole_shillings(price) {
            problems.append(
                _problem(
                    f"options[{i}].price_cents",
                    "PRICE_INVALID",
                    "Enter an extra price in whole shillings, from KES 0 to KES 100,000."
                )
            );
            price = 0;
        }
        given_id = row.get("option_id");
        option_id = given_id
            if isinstance(given_id, str) and re.fullmatch(r"[a-z0-9]{8,32}", given_id)
            else "";
        kept.append(
            AddonOptionFields(option_id=option_id, name=option_name, price_cents=price)
        );
    }
    low_given = _as_int(min_picks);
    high_given = _as_int(max_picks);
    low = low_given if low_given is not None else -1;
    high = high_given if high_given is not None else 0;
    can_repeat = bool(repeatable);
    if high < 1 or (not can_repeat and high > len(kept)) {
        problems.append(
            _problem(
                "max_picks",
                "MAX_INVALID",
                "Customers must be able to pick at least 1, and no more than there are add-ons."
            )
        );
    } elif low < 0 or low > high {
        problems.append(
            _problem(
                "min_picks",
                "MIN_INVALID",
                "The least customers pick can't be more than the most. Use 0 for optional."
            )
        );
    }
    if problems {
        return (None, problems);
    }
    return (
        AddonGroupFields(
            name=clean_name,
            label=clean_label,
            min_picks=low,
            max_picks=high,
            repeatable=can_repeat,
            options=kept
        ),
        []
    );
}

def check_components(
    components: any  # jac:ignore[W1037]
) -> tuple[list[ComponentFields] | None, list[dict[str, str]]] {
    problems: list[dict[str, str]] = [];
    given = _as_list(components);
    if not given or len(given) > COMPONENTS_MAX {
        problems.append(
            _problem(
                "components",
                "COMPONENTS_COUNT",
                f"A combo has 1 to {COMPONENTS_MAX} included items."
            )
        );
    }
    kept: list[ComponentFields] = [];
    for (i, raw) in enumerate(given[:COMPONENTS_MAX]) {
        row = _as_dict(raw);
        at = f"components[{i}]";
        label = _tidy(row.get("label"));
        if not label or len(label) > COMPONENT_LABEL_MAX {
            problems.append(
                _problem(
                    f"{at}.label",
                    "LABEL_INVALID",
                    f"Name this item, 1 to {COMPONENT_LABEL_MAX} characters."
                )
            );
        }
        given_quantity = _as_int(row.get("quantity"));
        quantity = given_quantity if given_quantity is not None else 0;
        if quantity < 1 or quantity > QUANTITY_MAX {
            problems.append(
                _problem(
                    f"{at}.quantity",
                    "QUANTITY_INVALID",
                    f"Include 1 to {QUANTITY_MAX} of it."
                )
            );
        }
        ids = [str(x) for x in _as_list(row.get("variant_ids"))];
        if not ids or len(ids) > CHOICES_MAX or len(set(ids)) != len(ids) {
            problems.append(
                _problem(
                    f"{at}.variant_ids",
                    "VARIANTS_INVALID",
                    f"Choose one product to include, or 2 to {CHOICES_MAX} for customers to choose from, each once."
                )
            );
        }
        kept.append(
            ComponentFields(
                label=label,
                quantity=quantity,
                kind="fixed" if len(ids) == 1 else "choice",
                variant_ids=ids
            )
        );
    }
    if problems {
        return (None, problems);
    }
    return (kept, []);
}

def combo_on_sale(components: list[ComponentFields], on_sale: dict[str, bool]) -> bool {
    # Every component can be filled: its fixed variant, or at least one of its
    # choices, is on sale (`on_sale` says, by variant id, for one venue).
    if not components {
        return False;
    }
    return all(any(on_sale.get(v, False) for v in c.variant_ids) for c in components);
}
