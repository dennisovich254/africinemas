# ADR-0042: Faster snack catalog work: templates, duplicate, CSV import and export, bulk actions

- **Status:** Accepted
- **Date:** 2026-10-11
- **Sub-phase:** P12.5
- **Code:** `core/snacks/importer.jac` (pure), `core/snacks/tools_api.jac`, `web/backoffice/snack_view.jac` (`TEMPLATES`, `template_form`), `SnackProductEditor.jac` (template picker, Duplicate, Add another), `SnackImportPage.jac`, `SnackProductsPage.jac` (bulk)
- **Tests:** `tests/unit/snack_import_tests.jac`, `tests/integration/snack_tools_tests.jac`, `e2e/snack_tools_tests.jac`

## Context
The design guide (§4) says cinemas onboard dozens or hundreds of snacks and shouldn't type each one. It asks for:
- templates;
- duplicate;
- "add another";
- CSV import (upload, map, preview, import) and export;
- bulk actions.

## Decision
1. **Templates are starting points, never rules.** Add product first offers:
   - Popcorn: Small, Medium, Large;
   - Beverage: 300 ml, 500 ml, 1 litre;
   - Packaged snack: a single item;
   - Combo;
   - a blank product.

   Each fills the editor, in its category if the cinema has one by that name, and everything stays editable. "Add another product" opens a new blank product in the same category.
2. **Duplicate makes a new draft, "Copy of …".** It copies:
   - the details, variants (values, prices, availability, Track stock), add-ons and combo items;
   - venue settings and stock alerts.

   It never copies SKUs (each must be new), images (they belong to the original's media) or stock (stock belongs to variant ids).
3. **CSV import is AfriCinemas' own format:** `product_name, category, brand, option, variant, sku, price, currency`, with one row per variant and prices in shillings. The steps:
   1. Columns are found by their usual names, and staff can map them.
   2. Rows with the same product name are one product. A row without a variant is a single item.
   3. The **preview** saves nothing. It reports every bad row with its row number:
      - a missing field;
      - an unknown category, unless "Make missing categories" is ticked;
      - a SKU twice in the file or owned by another product;
      - a price that isn't whole shillings, or a currency that isn't KES;
      - a product whose rows disagree;
      - a single item on two rows;
      - a change to an existing product's shape.
   4. The **import** runs the same checks and changes nothing unless there are none.
   5. An existing product (same name) is updated, with its variants matched by SKU. New SKUs are added and nothing is removed, so running the file again updates rather than duplicates.
   6. New products are drafts: nothing goes on sale until it's published.

   The export writes the same columns, so a cinema can round-trip its catalog. Combos and two-option variants stay in the editor.
4. **Bulk actions:** publish, archive or restore up to 200 products. Each answers for itself: a product that can't be published says why, and the others go through. Setting which venues sell many products at once is available as `bulk_snack_venues` (no screen yet).
5. **Permissions:** everything needs `concessions.manage`, except export, which needs `concessions.read`. Changes are audited (`snack_product.duplicated`, `snack_catalog.imported`, `snack_product.bulk_*`).

## Consequences
- The import reuses the product save path, so it obeys every catalog rule (SKU claims, validation) without its own copy of them.
- A cinema's import runs in one request. Files are capped at 1 MB and 2,000 rows. Larger catalogs import in parts.
