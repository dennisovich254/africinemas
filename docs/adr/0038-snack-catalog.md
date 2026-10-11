# ADR-0038: The snack catalog: categories, products and variants, with a draft → active → archived lifecycle

- **Status:** Accepted
- **Date:** 2026-10-11
- **Sub-phase:** P12.1
- **Code:**
  - `core/snacks/models.jac` (`SnackCategory`, `SnackProduct`, `SnackVariant`)
  - `core/snacks/catalog.jac` (the pure checks)
  - `core/snacks/store.jac`, `category_api.jac`, `product_api.jac`
  - `core/authz/policy.jac` (`concessions.*`)
  - `web/backoffice/SnackProductsPage.jac`, `SnackProductEditor.jac`, `SnackCategoriesPage.jac`, `snack_view.jac`
- **Tests:** `tests/unit/snack_catalog_tests.jac`, `tests/unit/authz_tests.jac`, `tests/integration/snack_catalog_tests.jac`, `tests/isolation/`, `e2e/snack_catalog_tests.jac`

## Context
Cinemas sell popcorn in three sizes, sodas in several sizes and flavours, crisps by brand and pack size, combos and extras. The user asked for the design in their guide, "Designing the Snack Management System for a Multitenant Cinema Platform" (`docs/snacks-guide.md`, 2026-10-11). It replaces a first attempt, simple items with shared option lists, which was set aside on the local branch `archive/p12.1-first-try`. Phase 12 builds the whole catalog, venues, add-ons, combos, stock and the productivity tools before customers can buy (user decision 2026-10-11). This ADR covers the catalog foundation.

## Decision
1. **Separate concepts, as the guide sets out:**
   - a **category** organizes products;
   - a **product** is a family (Popcorn, Coca-Cola);
   - a **variant** is what a customer buys (Medium; Zero Sugar · 500 ml).

   Sizes, flavours and brands are never categories. A product is *single* (one variant, no options) or *with variants*: up to two option axes, where the variants are the combinations the cinema sells, never forced to be all of them. Combos and add-ons come in P12.3.
2. **Three tenant nodes:**
   - `Tenant → SnackCategory`;
   - `Tenant → SnackProduct → SnackVariant`.

   Each is owned by the cinema's principal and attached to its access group (ADR-0004). Every id a caller sends is checked against the cinema (ADR-0008), so another cinema's product or category is `not_found`, and a category from elsewhere is a problem on `category_id`.
3. **Variants have persistent ids.** The editor sends every row with its id; an unknown or absent id makes a new variant, and a variant not sent is removed. Orders, stock and venue prices will point at these ids whatever staff rename.
4. **SKUs are unique in the cinema.** Each SKU (kept in capitals) is an atomic claim held by its variant's id (ADR-0007):
   - it is provisional until the save commits;
   - a SKU freed by a change, a removed row or a deleted draft is released on commit;
   - a SKU another product holds is a field problem naming that product.

   A barcode is optional, 8–14 digits.
5. **The lifecycle is a state, not a flag:**
   - `draft → active` by **publish**, validated on the server;
   - `active → draft` by **unpublish**;
   - draft or active `→ archived`;
   - `archived → draft` by **restore**.

   A draft may leave SKUs and prices empty. Publishing needs:
   - an active category;
   - at least one variant;
   - a price and a SKU on every variant;
   - at least one variant available.

   An active product must stay sellable when edited. Only a draft can be deleted; anything else is archived, so orders and reports keep reading it.
6. **Problems are field-level**, as the guide's example shows:
   - each is `{field, code, message}`, with fields such as `variants[1].price_cents`, codes such as `PRICE_REQUIRED`, and messages that name the variant;
   - all of them come back at once, under `invalid_product` (save) or `cannot_publish` (publish);
   - the editor shows each one beside its field.
7. **Prices** are whole KES cents (KES 1 to KES 100,000), in the cinema's currency, never typed into the model by hand. Per-venue prices and availability come in P12.2.
8. **Images** go through the poster pipeline (`process_snack_photo`): checked, re-encoded as WebP, up to five per product, the first the main one. A removed image is deleted on commit.
9. **Permissions on existing roles** (user decision 2026-10-10):
   - `concessions.read`: managers, box office, finance, auditors;
   - `concessions.manage`: owner, tenant admin, general manager;
   - `concessions.availability`, `concessions.inventory` and `concessions.collect`: managers and the box office, used from P12.2, P12.4 and P12.9.

   Reading needs the permission anywhere in the cinema, so venue-scoped box office staff can read the catalog.
10. **The back office follows the guide's screens:**
    - a **Products** list with counts, a prominent search (name, brand, SKU or barcode), category and status filters, and "3 variants · POP-SM … From KES 200 … Active";
    - a dedicated **product editor page** with sections for Product information, Images, Variants & pricing and Publishing, an inline variant table, a storefront preview, and an unsaved-changes warning;
    - a **Categories** page: the usual six in one tap, rename, order, archive.
11. **Every change is audited** (`snack_category.*`, `snack_product.*`).

## Consequences
- Search runs over the cinema's whole catalog in one read. This is fine at the guide's scale (hundreds of products). Paging and server-side search can follow when a cinema's catalog outgrows it.
- Swapping two variants' SKUs in one save is refused (the second claim sees the first). Staff change them one at a time.
- Templates, duplicate, CSV import and bulk actions are P12.5. Location settings are P12.2, add-ons and combos P12.3, and stock P12.4. None of them changes this model; each adds to it.
