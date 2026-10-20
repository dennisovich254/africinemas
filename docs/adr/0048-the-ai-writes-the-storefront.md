# ADR-0048: The AI writes each cinema's storefront

- **Status:** Accepted
- **Date:** 2026-10-20
- **Sub-phase:** Deferred AI features: AI brand-theme generator, phase (e)
- **Code:**
  - `core/theming/pagecode.jac`: `BRIEF`, `sanitize`, `clean_css`, `bundled_fonts`, `write_page`.
  - `core/theming/branding_api.jac`: `design_storefront`, publish, rollback, `public_branding`.
  - `core/theming/models.jac`: `Branding.draft_page`, `ThemeVersion.page`.
  - `core/theming/suggest.jac` and `core/theming/brandkit.jac`: the newest models.
- **Tests:** `tests/unit/pagecode_tests.jac`, `tests/unit/theme_suggest_tests.jac`, `tests/integration/brand_kit_tests.jac`, fixture `tests/fixtures/ai_storefront.html`

## Context
ADR-0047 has the AI choose each storefront's design from designed options. The owner wanted more: the AI designing the storefront itself (option C). Two prototypes (2026-10-20) tested this.
- **A static page.** Gemini Pro Latest wrote whole pages from three logos. They were distinct and readable, but a static page can't show tomorrow's showtimes or take a booking.
- **A template.** The model wrote the page with data slots, and our code filled them. All three templates came back complete, in 80 to 130 s each, and none scrolled sideways from 390 px to 1440 px.

## Decision
1. **The model writes a template, never the data.** The model is Gemini Pro Latest (`MODELS`), then 3.8 Flash. It writes the header, the home page and the footer in its own HTML, CSS and drawn SVG ornaments. It marks where the programme goes, and the storefront fills those slots:
   - `data-each` for the lists: featured, films, a film's times, today, coming soon;
   - `data-empty` for what shows when a list is empty;
   - `data-text` for text, `data-img` for the logo and posters, `data-link` for our routes;
   - `data-part` for the header, home and footer.

   Booking, seats, accounts and payment stay ours.
2. **Nothing it writes is trusted.** `sanitize` keeps only allowlisted HTML and SVG tags and attributes, and rewrites the text. It drops, together with their content:
   - scripts, event handlers and inline styles;
   - `src` and `href`, except SVG's `href="#id"`;
   - forms, frames and media.

   The stylesheet is parsed (tinycss2), and only safe declarations survive:
   - no `@import`, `@font-face` or `url()` (except `url(#id)` for SVG paint);
   - no `position: fixed`, and no expressions;
   - every selector is scoped inside `.ai-page`.

   Font families become the bundled fonts, so no request leaves the page.
3. **Complete, or asked again.** A template must have its three parts, the five lists, the book, sign-in, showtime and film links, the logo and "Tickets by AfriCinemas". If any is missing, the model is asked once more, with what it left out. If it still fails, there is no page.
4. **One button.** `design_storefront` writes the page next to the theme and the kit, at the same time, and waits up to `PAGE_DEADLINE` (320 s). A failed page leaves the designed storefront from ADR-0047 in its place. The page is the draft's, private until published, and carried by versions and rollback. Remove brand removes it too. `public_branding` serves its HTML and CSS.
5. **Cost.** A page is about 8,000 to 11,000 output tokens plus 3,000 to 16,000 of thinking, roughly $0.15 to $0.30. It is part of the 3 designs a day (`KIT_DAILY`).
6. **The newest models everywhere.** Themes and the kit's plan use Gemini 3.8 Flash, then Flash Latest. Gemini 3.x can't turn thinking off (it refuses "minimal"), so 3.x thinks at "low" with 4,000 tokens of room, and 2.5 still doesn't think. Motifs are drawn by Gemini 3.1 Flash Image.

## Consequences
- Each cinema's storefront can look like nothing else, and still books through our code.
- **Quality varies from run to run.** The owner previews the page before publishing, and can design again (3 a day).

## The storefront draws it
`web/storefront/AiPage.jac` turns the stored template into the live page.
- **Never inserted as HTML.** The template is parsed with the browser's `DOMParser` and drawn as React elements. The same allowlist applies again: no events, no `src`, and no `href` but ours. SVG attribute names are spelled the way React expects.
- **Filled from `public_home`** (narrowed to the visitor's chosen venue):
  - `featured` is the hero film, or else the first film on sale;
  - `films` are the films on sale, each with its next times;
  - `today` is the first day's showtimes;
  - `soon` is the coming soon list.

  Posters load like any poster, and links go to our routes: the movie page, the showtime page, sign-in, my tickets, and `#showtimes` / `#coming-soon`.
- **Its header and footer frame every storefront page.** Its home part is the home page. Each part sits in its own `.ai-page` wrapper, the stylesheet's scope, so the AI's CSS never reaches our movie, checkout or ticket pages between them. The search and venue picker of our own header aren't in a written header.
- **Preview before publishing.** The Branding page shows the written page filled with the cinema's real programme. Designing takes about 2 minutes.
