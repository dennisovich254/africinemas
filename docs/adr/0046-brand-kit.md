# ADR-0046: A brand kit drawn from each cinema's logo

- **Status:** Accepted
- **Date:** 2026-10-20
- **Sub-phase:** Deferred AI features: AI brand-theme generator, phase (c)
- **Code:** `core/theming/brandkit.jac` (`plan_kit`, `as_mask`, `draw_kit`, `checked_look`), `core/theming/branding_api.jac` (`draw_brand_kit`, `set_brand_look`, `remove_brand_kit`, publish, rollback, `public_branding`), `core/theming/models.jac`
- **Tests:** `tests/unit/brandkit_tests.jac`, `tests/integration/brand_kit_tests.jac`, `tests/isolation/registry.jac`

## Context
The pattern drawn from the logo (ADR-0045) sat behind the storefront like wallpaper, so the owner found it looked separate from the site in every style. A prototype for Rupa's Mall (2026-10-20) put the logo's doves and open frame *inside* the storefront's parts instead: by headings, in dividers, on the ticket, breaking out of the hero's frame. It used single-colour shapes painted with theme colours and component variants echoing the logo's shapes. The owner wanted that done uniquely for every cinema.

## Decision
1. **A kit, not wallpaper.** A cinema's brand kit is up to two **motifs** (masks: shape on clear) and a **look**: card (notched, sharp, rounded), frame (open, full, none), divider (motif, row, line) and heading (caps, natural).
2. **The plan.** Gemini (byLLM, a typed `BrandPlan` with enum fields) looks at the logo and names the motifs worth drawing, a single figure first and then optionally a group, and picks the look. A lettering-only logo may have no motifs. Any unknown value becomes the default look's, and a failed plan gives no motifs and `DEFAULT_LOOK`. A motif divider with no motif becomes a line.
3. **The motifs.** Gemini's image model draws each named motif from the logo as a black silhouette on white, using the logo itself as the reference. Code turns each drawing into a mask: dark is shape, white or transparent is clear. The mask is cropped, at most 320 px and re-encoded as WebP. A blank or solid drawing is dropped, and a failed motif is left out.
4. **Like the logo.** The kit is the draft's, private until published, and carried by versions and rollback. `public_branding` serves it with masks as data URLs. The storefront paints masks with theme colours (PR 2), so a motif always matches the theme in both light and dark.
5. **Limits.** A kit is one plan and up to two drawings, about $0.09 and 8 to 15 s. Each cinema gets 3 a day (`kit_limit`). It needs the draft logo (`no_logo`) and `tenant.settings.update`, and is audited (`theme.kit_drawn`, `theme.kit_styled`, `theme.kit_removed`). The owner may switch the look among the designed values (`set_brand_look`) but not compose their own.

## Real runs (2026-10-20)
- **Rupa's Mall:** sharp cards, open frame, row divider, caps headings; motif "three birds in flight".
- **Flowers and bird:** rounded cards, no frame, row divider, natural case; motifs "three flowers" and "a pennant" (the bird read as a flag, which is why the owner can draw again).
- **Wordmark only:** no motifs, plain line, caps, sharp cards.

## Consequences
- Every cinema's storefront can carry its own motifs and shapes, placed in designed spots, with no free composition.
- The pattern (ADR-0045) is replaced once the storefront wears the kit (PR 3 removes it).
