# ADR-0049: Claude for every AI feature; the logo's figures cut from the logo

- **Status:** Accepted
- **Date:** 2026-10-20
- **Sub-phase:** Deferred AI features: AI brand-theme generator, phase (f)
- **Code:**
  - `core/ai/claude.jac`: `ask_json`, `ask_text`, `image_block`, `ClaudeFailed`.
  - `core/theming/brandkit.jac`: `plan_schema`, `plan_kit`, `cut_motif`, `draw_kit`.
  - `core/theming/suggest.jac`: `theme_schema`, `proposal_from`, `ask`.
  - `core/theming/pagecode.jac`: on the shared helper.
  - `core/theming/logo.jac`: `edge_backdrop`.
  - `core/theming/branding_api.jac`: `design_storefront`, `_mask_url`.
  - `web/backoffice/BrandingSection.jac`: the design note.
- **Tests:** `tests/unit/brandkit_tests.jac`, `tests/unit/theme_suggest_tests.jac`, `tests/unit/logo_tests.jac`, `tests/integration/brand_kit_tests.jac`, `tests/integration/theme_suggest_tests.jac`, `e2e/brand_kit_tests.jac`

## Context
Warui's storefront looked weak live (2026-10-20), though Claude had written its page. The Gemini account's prepaid credits had run out, so every Gemini call answered `402`. Everything around the page then fell back silently:
- no figures, so the page's seven motif slots were empty;
- the default look;
- colours built by code instead of designed.

Warui's logo also still sat on a white box: its artwork touches one corner, and the clean-up needed all four corners to agree. The owner decided to drop Gemini entirely and use Claude for everything.

## Decision
1. **One helper, one model.** Every model call goes through `core/ai/claude.jac`.
   - **The call:** Claude Opus 5.5 through the official SDK, streamed, with adaptive thinking at the caller's effort.
   - **Fallbacks:** `fallbacks: "default"` (beta `server-side-fallback-2026-07-01`), so a declined request is retried server-side.
   - **Two forms:** `ask_json` holds the answer to a JSON schema (structured outputs); `ask_text` returns text.
   - **Failures:** a provider error, refusal, cut-off answer or missing `ANTHROPIC_API_KEY` raises `ClaudeFailed`, and the caller falls back on its own terms.

   The SDK lives in the inline Python block, because the Jac checker can't read its HTTP library.
2. **Themes:** `suggest` asks for one theme against `theme_schema`. Each colour role is a string, and the fonts, corners, scheme and template are enums of the allowed values. The answer becomes a `ThemeProposal` and is checked and repaired as before. byLLM, the Gemini model list and the per-model thinking rules are gone.
3. **The brand plan:** one `ask_json` against `plan_schema`. It returns the look, every part an enum of its designed values, and a tagline. It also returns up to two figures, each with a name, a box in the logo's pixels and its body colour; Claude is told the logo's size.
4. **The figures come from the logo itself.** No image model draws anything.
   - `cut_motif` keeps the opaque pixels near the figure's colour inside its box, so a tree on a sunset keeps the tree.
   - It drops specks, and small pieces cut off at the box's edge (bits of letters).
   - It enlarges and smooths the cut-out, then traces it with potrace (`potracer`, pure Python) into smooth filled paths.
   - The result is an SVG made by our code, stored with `"type": "svg"` and served as `data:image/svg+xml`. Older kits' WebP masks are still served.
   - An empty box or a solid block is left out.
5. **Logos:** the backdrop is the colour at least 60% of the edge shares (`edge_backdrop`), cleared from every edge pixel of that colour, not just the corners. `design_storefront` cleans the draft logo too, so logos uploaded before the clean-up are fixed when the owner designs.
6. **No silent fallbacks:** `design_storefront` reports `from_ai` (the colours) and `kit_from_ai` (the plan). The Branding page names any step that didn't answer and asks the owner to design again before publishing.

## Real runs (2026-10-20)
- **Rupa's Mall:** plan and figures in 5.1 s: "one dove in flight" and "three doves in flight", the logo's own doves. Theme in 23 s: "Golden Flight Gala", dark. Tagline: "Where every show takes flight".
- **Kijiji Cinema:** plan and figures in 4.3 s: a clean acacia tree, without the sun's stripes, and the sunset emblem. Theme in 19.5 s: "Savanna Gold Hour", light.

## Consequences
- One provider and one key (`ANTHROPIC_API_KEY`) for the storefront's AI. A lapsed account shows up in the Branding note, not as a quietly weaker page.
- **Faithful figures:** they are the logo's own shapes, as faithful as its pixels. A very small logo gives softer edges, and potrace smooths them.
- **Still on Gemini:** the booking chat agent (`core/agent`), until it moves to Claude next.
