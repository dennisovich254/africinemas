# ADR-0040: Snack add-ons and combos

- **Status:** Accepted
- **Date:** 2026-10-11
- **Sub-phase:** P12.3
- **Code:** `core/snacks/extras.jac` (pure checks), `core/snacks/extras_api.jac`, `core/snacks/models.jac` (`SnackAddonGroup`; product `addon_group_ids`, `components`), `web/backoffice/SnackExtrasPage.jac`, `SnackExtrasParts.jac`
- **Tests:** `tests/unit/snack_extras_tests.jac`, `tests/integration/snack_extras_tests.jac`, `e2e/snack_extras_tests.jac`

## Context
The design guide (§5) separates three things:
- a **variant** (Large Popcorn is a different thing to buy);
- an **add-on** (extra butter customizes it);
- a **combo** (a bundle at its own price, sometimes with a choice inside).

They differ in price, stock, reporting and fulfillment, so they are modeled apart.

## Decision
1. **Add-on groups are tenant nodes (`SnackAddonGroup`), shared by the products they're attached to** (`product.addon_group_ids`, up to 5). Each group has:
   - an internal name and the label customers see;
   - pick limits: 0 makes it optional, and max can't exceed the options unless an add-on may repeat;
   - 1–20 add-ons, each with a name, an extra price from KES 0 to KES 100,000, and the venues where it's unavailable.

   Editing keeps each add-on's id and venue switches. A group offered with a product can't be deleted. Sizes are never add-ons; they stay variants.
2. **A combo is a product of kind `combo`.** It is sold as one item: its one variant carries the SKU and the combo price. Its `components` are each a label, a quantity, and either one fixed variant or a choice of 2–30 eligible variants. Components must come from the cinema's own non-combo products, so there is no nesting and nothing from another cinema. A combo can't be published without components.
3. **A combo sells only where every component can be filled** (`combo_on_sale`): the fixed variant, or at least one eligible variant, is on sale at that venue. This enforces the guide's rule that a combo must not sell an out-of-stock component. Stock joins this in P12.4.
4. **Who changes what:**
   - groups, which products offer them, and combo contents are managers' (`concessions.manage`);
   - an add-on's availability at a venue is also the box office's (`concessions.availability` at that venue).

   Every id is checked against the cinema, problems come back by field, and every change is audited.
5. **The back office:**
   - a **Combos & Add-ons** page lists the add-on groups (editor, "offered with N products", per-venue switches) and the combos;
   - the product editor gains **Add-ons** (a checklist of groups) and, for combos, **What the combo includes** (rows of label, quantity and ticked products, where one ticked means always included and several mean the customer chooses).

## Consequences
- Prices: the order (P12.7) prices a combo at its own price plus any add-ons. The customer's choices inside a combo don't change the price.
- An add-on's stock (for example butter) is not tracked. P12.4 tracks finished items per variant, and recipes come later, as the guide advises.
