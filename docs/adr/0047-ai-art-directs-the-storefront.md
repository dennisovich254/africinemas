# ADR-0047: The AI art-directs each cinema's storefront from its logo

- **Status:** Accepted
- **Date:** 2026-10-20
- **Sub-phase:** Deferred AI features: AI brand-theme generator, phase (d)
- **Code:**
  - `core/theming/brandkit.jac`: `BrandPlan`, `LOOK_PARTS`, `checked_look`, `checked_tagline`, `plan_kit`.
  - `core/theming/logo.jac`: `clear_backdrop`, `logo_ink`, `readable_scheme`.
  - `core/theming/branding_api.jac`: `upload_logo`, `set_brand_look`, `_public_kit`.
  - `core/theming/suggest.jac`: `suggest_from_logo`.
- **Tests:** `tests/unit/logo_tests.jac`, `tests/unit/brandkit_tests.jac`, `tests/integration/brand_kit_tests.jac`

## Context
The brand kit (ADR-0046) put the logo's motifs inside the storefront's parts. The owner still found the storefront "off", whatever was tuned, for three reasons:
- **Logos looked pasted in.** A logo on a white box sat on the page as a white rectangle.
- **The template's look was fixed.** The fonts, the hero and the full-screen backdrop were the same for every cinema, and the fonts often clashed with the logo's lettering.
- **A pale logo disappeared.** On a light page, Rupa's Mall's gold logo had a contrast of 1.39.

A prototype (2026-10-20) rendered three very different logos with one renderer. The AI chose each storefront's design system from a few designed options per part. The owner approved the direction, and asked that the owner choose less and less.

## Decision
1. **The plan is a design system.** `BrandPlan` keeps the motifs and the card, frame, divider and heading choices. It now also picks:
   - **fonts:** one of eight designed font pairings (gallery, marquee, editorial, luxe, bold, friendly, modern, heritage);
   - **header:** logo left, or logo centred above the links;
   - **hero:** a framed poster, a centred crest, or split;
   - **surfaces:** flat, outlined or filled;
   - **density:** airy or compact;
   - **tagline:** a short line of 3 to 7 words.

   The prompt asks the model to match the headings to the logo's lettering (weight, width, spacing, serifs, case) before the mood.
2. **Still designed values only.** Each part is an enum; anything unknown falls back to `DEFAULT_LOOK`'s choice. The tagline is cleaned to one line of at most 60 characters with no quotes.
3. **Older kits keep working.** `checked_look` requires only the original four parts and gives the others their defaults. `public_branding` always serves the full look. `set_brand_look` changes only the parts sent, so a change keeps the rest of what the AI chose.
4. **Logos are cleaned on upload.** If a logo has no transparency of its own and its four corners share one colour, that colour is cleared where it connects to the edges:
   - the edges are soft, so no halo is left;
   - the same colour inside the logo stays;
   - the margins are trimmed.

   A logo that is transparent already, has mixed corners, or would be left empty or a speck is kept as uploaded.
5. **The logo must show in the visitor's mode.** The logo's average visible colour must have a contrast of at least 2.0 with the page background in the mode visitors see. If it doesn't, the suggested theme's scheme switches to the mode where the logo stands out more. For `auto`, this applies when either mode fails.

## Consequences
- The storefront renderer (next) reads the look's parts to set the fonts, header, hero, surfaces and spacing per cinema. The full-screen backdrop hero goes away.
- The owner's controls shrink. One action designs the storefront, and the owner previews and publishes it.
- Each part costs no extra model calls: it is the same plan call as the kit.
