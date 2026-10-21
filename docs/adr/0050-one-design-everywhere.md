# ADR-0050: One design across the whole storefront; the page reviewed before it is kept

- **Status:** Accepted
- **Date:** 2026-10-21
- **Sub-phase:** Deferred AI features: AI brand-theme generator, phase (g)
- **Code:**
  - `core/theming/pagereview.jac`: `filled_document`, `programme_lists`, `sample_lists`, `review_page`.
  - `core/theming/branding_api.jac`: `design_storefront`, `brand_system`, `_review_lists`, `_write_reviewed`.
  - `core/theming/pagecode.jac`: `brand_brief`, `brief`, `write_page`.
  - `core/theming/brandkit.jac`: `FONT_FAMILIES`.
- **Tests:** `tests/unit/pagecode_tests.jac`, `tests/unit/pagereview_tests.jac`

## Context
On warui's storefront (2026-10-21), the AI-written home page and the movie page between its header and footer looked like two sites:
- **Fonts:** the page chose Raleway; the movie page wore the kit's pairing, Sora.
- **Colours:** the page used its own golds; the movie page used the theme's.
- **Corners:** the page was square; the movie page had rounded cards.

The page writer ran at the same time as the colours and the brand plan, so it never saw them.

## Decision
1. **The colours and brand plan come first.** `design_storefront` runs the theme and the kit side by side (about 20 s), then writes the page in that system (`brand_system`):
   - the colours of the scheme visitors see (background, surface, raised, border, ink, muted, accent, on-accent, accent ink, link, focus ring);
   - the kit's font pairing, as families (`FONT_FAMILIES`, exactly what `styles/design.css` uses for the rest of the storefront);
   - the corner style from the kit's card shape;
   - the figures in the motif slots, and the tagline.
2. **The brief says to use them exactly** (`brand_brief`): define the colours as CSS custom properties on `.ai-page` and use only those, plus transparent tints, because the movie, checkout and ticket pages wear the same. A logo with no figures is told to leave out the motif slots, so none are left empty.
3. **One scheme for every page.** A written page has one palette. A theme left on `auto` is pinned to the mode its light background suits, so the device's mode can't flip our pages while the written page stays the same.

## The page is reviewed before it is kept
On warui's storefront, a design meant for a full programme came out sparse and oversized for one film, and a decoration covered a poster. Claude had never seen the page it wrote. `core/theming/pagereview.jac` lets it.
1. **Rendered as visitors see it.** `filled_document` fills the template the way `web/storefront/AiPage.jac` does: lists, empty states, text, the logo, 2:3 posters drawn above decorations, and the figures painted through their masks. It uses the cinema's real programme and posters (`programme_lists`), or a small sample programme when the cinema has published none (`sample_lists`).
2. **Screenshotted:** Playwright's headless Chromium takes a desktop shot (1280 px) and a phone shot (390 px), each at most 3,200 px tall.
3. **Reviewed:** Claude gets the logo, both screenshots, its own template and the brand system, reviews the page as an art director, and returns the corrected template.
4. **Never worse:** the answer passes `sanitize` like any written page. If there are no screenshots (no browser installed), the model fails, or the template is incomplete, the page is kept as written. Browser tests, whose page is scripted, skip the review.

`PAGE_DEADLINE` is 780 s.

**A real run on Rupa's logo (2026-10-21):** colours and plan 20 s, page 156 s, review 179 s, about 6 minutes in all. The review:
- moved doves that collided with the hero title and the footer links;
- shrank section frames to their content instead of stretching them across empty space;
- set the heading figures beside the titles.

Neither version scrolled sideways at 390 or 1280 px.

**Production:** the server needs the browser: `python -m playwright install --with-deps chromium-headless-shell`. Playwright moves from dev to production dependencies. Without the browser, designs still work, unreviewed.

## Consequences
- Header, home page, footer and the booking pages between them share colours, fonts and corners.
- A design takes about 6 minutes instead of 3, and costs about $0.80 instead of $0.40.
- **A long request:** a reverse proxy with a short read timeout (nginx's default is 60 s) would cut it off, so the Design request needs a long timeout. A background job with progress would be the robust form, if this is ever a problem.
