# ADR-0045: A decorative pattern drawn from the cinema's logo

- **Status:** Accepted
- **Date:** 2026-10-19
- **Sub-phase:** Deferred AI features: AI brand-theme generator, phase (b)
- **Code:** `core/theming/pattern.jac` (`pattern_prompt`, `draw_pattern`, `as_webp`, `checked_places`), `core/theming/branding_api.jac` (`draw_pattern`, `remove_pattern`, `set_pattern_places`, publish and rollback), `core/theming/models.jac`, `web/backoffice/BrandingSection.jac` (Pattern from your logo), `web/storefront/StorefrontShell.jac`, `HomeSections.jac`, `TicketsPage.jac`, `MyTicketsPage.jac` (`data-pattern-slot`), `styles/brand.css`
- **Tests:** `tests/unit/pattern_tests.jac`, `tests/integration/theme_pattern_tests.jac`, `e2e/branding_tests.jac` (a pattern drawn from the logo), `tests/isolation/registry.jac`

## Context
The owner asked that features in a logo, such as flowers or birds, appear on the cinema's website, and chose AI-drawn patterns over a shipped library of motifs (2026-10-19), shown in places the owner picks.

## Decision
1. **Gemini draws from the logo itself.** `draw_pattern` sends the logo and a brief to `gemini-2.5-flash-image` (`AFRICINEMAS_PATTERN_MODEL`) through the REST `generateContent` API. byLLM's image generation takes text only, and the logo is the reference that makes the motifs the cinema's own. The brief asks for a seamless, light, repeating pattern of the logo's motifs as flat illustrations. It uses only the theme's accent, link, accent-ink and muted colours, on the page colour of its scheme (dark for a dark theme), with plenty of empty space and no text, letters, logos or faces. The theme is the one being edited, saved or not.
2. **Only a checked image is kept.** The answer is decoded and re-encoded as WebP, at most 1024 px on a side. Transparency is kept, so the page's own colour shows through; flattening it first turned a transparent ground black, which would darken a light page. Anything that isn't an image is refused. The model's answer is never put on a page as it came.
3. **It's the draft's, like the logo.** The drawing is the draft's pattern, private until published. `remove_pattern` takes it off the draft. Publishing puts the pattern and its places on the new `ThemeVersion` and on the storefront; rolling back restores them. A first drawing is shown behind the hero and in the footer, and the owner then picks among hero, header, home page sections, footer and ticket pages (`set_pattern_places`).
4. **On the storefront it never competes with text.** The root carries the chosen places (`data-pattern`) and the image (`--ac-pattern`), and each part that can wear it is marked `data-pattern-slot`. A `::before` layer repeats the image at 360 px and 14% opacity under the part's content (`z-index: -1` in its own stacking context), so contrast checks on the theme still hold. In the hero, a movie's backdrop covers it.
5. **Cost and safety.** A drawing took 13.5 s and about 1,300 output tokens, roughly $0.04. Each cinema gets 3 a day (`pattern_limit`), counted before the call, with a 60 s timeout. It needs the draft logo (`no_logo`) and `tenant.settings.update`, is audited (`theme.pattern_drawn`, `theme.pattern_removed`, `theme.pattern_placed`), and a failure says so (`pattern_failed`). Browser tests supply the drawing from a file (`AFRICINEMAS_PATTERN_SCRIPT`), never the real model.

## Consequences
- Each cinema's storefront can carry its own motifs, drawn in its colours. A drawing varies in quality, which is why the owner previews it and can draw again or remove it.
- The image model's seams aren't always perfect; at 14% opacity and 360 px a seam is faint.
- A pattern is stored inline as base64 on the draft, each version and the storefront, like the logo (ADR-0013). At most 1024 px as WebP, it is tens to a few hundred kilobytes.
