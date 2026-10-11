"""P12.3: add-on groups and combos (core/snacks/extras.jac), as pure logic. Design guide §5.

- An add-on group: an internal name ("Popcorn extras", 1–40), what customers see
  ("Choose your extras", 1–60), pick limits (0 ≤ min ≤ max, max ≥ 1, and max ≤ the
  options unless an option may be picked more than once), and 1–20 options, each a name
  (1–40, unique ignoring case) and an extra price (KES 0 to KES 100,000). An option keeps
  its id; new ones get theirs from the endpoint.
- A combo's components: 1–6, each a label (1–40), a quantity (1–10) and either one fixed
  variant or a choice of 2–30 eligible variants (none repeated).
- A combo is on sale at a venue only if every component can be filled there: its fixed
  variant, or at least one eligible variant, is on sale there.
"""

import from core.snacks.extras {
    check_addon_group,
    check_components,
    combo_on_sale,
    AddonGroupFields,
    ComponentFields
}

def _options(*names: str) -> list[dict[str, any]] {  # jac:ignore[W1037]
    return [{"name": n, "price_cents": 0} for n in names];
}

def _fields(problems: list[dict[str, str]]) -> list[str] {
    return sorted([p["field"] for p in problems]);
}

test "a good add-on group is tidied and kept" {
    (fields, problems) = check_addon_group(
        " Popcorn  extras ",
        " Choose your extras ",
        0,
        2,
        False,
        [
            {"name": " Extra butter ", "price_cents": 3000},
            {"option_id": "a1b2c3d4e5f6", "name": "Caramel", "price_cents": 5000},
            {"name": "Cheese", "price_cents": 4000}
        ]
    );
    assert problems == [] and fields is not None , problems;
    kept = fields as AddonGroupFields;
    assert kept.name == "Popcorn extras" and kept.label == "Choose your extras";
    assert (kept.min_picks, kept.max_picks, kept.repeatable) == (0, 2, False);
    assert [o.name for o in kept.options] == ["Extra butter", "Caramel", "Cheese"];
    assert [o.price_cents for o in kept.options] == [3000, 5000, 4000];
    assert [o.option_id for o in kept.options] == ["", "a1b2c3d4e5f6", ""];
}

test "pick limits fit the options, unless options may repeat" {
    three = _options("Butter", "Caramel", "Cheese");
    assert _fields(check_addon_group("Extras", "Extras", 0, 4, False, three)[1])
        == ["max_picks"];
    assert check_addon_group("Sauces", "Sauces", 0, 4, True, three)[1] == [];
    assert _fields(check_addon_group("Extras", "Extras", 3, 2, False, three)[1])
        == ["min_picks"];
    assert _fields(check_addon_group("Extras", "Extras", 0, 0, False, three)[1])
        == ["max_picks"];
}

test "every problem with an add-on group is reported by field" {
    (fields, problems) = check_addon_group(
        "",
        "x" * 61,
        0,
        1,
        False,
        [
            {"name": "Butter", "price_cents": 0},
            {"name": " butter ", "price_cents": -100},
            {"name": "", "price_cents": "50"}
        ]
    );
    assert fields is None;
    assert _fields(problems)
        == [
            "label",
            "name",
            "options[1].name",
            "options[1].price_cents",
            "options[2].name",
            "options[2].price_cents"
        ] , problems;
    assert _fields(check_addon_group("Extras", "Extras", 0, 1, False, [])[1])
        == ["max_picks", "options"];
}

test "combo components are fixed or a choice, with quantities" {
    (kept, problems) = check_components(
        [
            {"label": " Popcorn ", "quantity": 1, "variant_ids": ["v-large-popcorn"]},
            {
                "label": "Drinks",
                "quantity": 2,
                "variant_ids": ["v-coke-500", "v-fanta-500"]
            }
        ]
    );
    assert problems == [] and kept is not None , problems;
    parts = kept as list[ComponentFields];
    assert [p.label for p in parts] == ["Popcorn", "Drinks"];
    assert [p.kind for p in parts] == ["fixed", "choice"];
    assert [p.quantity for p in parts] == [1, 2];
    assert parts[1].variant_ids == ["v-coke-500", "v-fanta-500"];
}

test "every problem with the components is reported by row" {
    (kept, problems) = check_components(
        [
            {"label": "", "quantity": 0, "variant_ids": []},
            {"label": "Drinks", "quantity": 11, "variant_ids": ["a", "a"]}
        ]
    );
    assert kept is None;
    assert _fields(problems)
        == [
            "components[0].label",
            "components[0].quantity",
            "components[0].variant_ids",
            "components[1].quantity",
            "components[1].variant_ids"
        ] , problems;
    assert _fields(check_components([])[1]) == ["components"];
}

test "a combo sells only where every component can be filled" {
    parts = (
        check_components(
            [
                {"label": "Popcorn", "quantity": 1, "variant_ids": ["large"]},
                {"label": "Drinks", "quantity": 2, "variant_ids": ["coke", "fanta"]}
            ]
        )[0]
    )
        or [];
    on_sale = {"large": True, "coke": False, "fanta": True};
    assert combo_on_sale(parts, on_sale);
    assert not combo_on_sale(parts, {** on_sale, "fanta": False});
    assert not combo_on_sale(parts, {** on_sale, "large": False});
    assert not combo_on_sale(parts, {"coke": True});
}
