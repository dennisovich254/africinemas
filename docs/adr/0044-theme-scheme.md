# ADR-0044: A theme's scheme: the cinema chooses light, dark or the visitor's device

- **Status:** Accepted
- **Date:** 2026-10-19
- **Sub-phase:** Deferred AI features: AI brand-theme generator
- **Code:** `core/theming/tokens.jac` (`SCHEMES`, `Theme.scheme`), `core/theming/branding.jac` (`parse_theme`, `OPTIONAL_KEYS`), `core/theming/suggest.jac` (`ThemeProposal.scheme`), `web/theme/ThemeProvider.jac` (`mode`), `web/storefront/StorefrontShell.jac`, `web/backoffice/BrandingSection.jac` (Light or dark), `web/backoffice/branding_model.jac` (`scheme_of`)
- **Tests:** `tests/unit/branding_tests.jac`, `tests/unit/theme_suggest_tests.jac`, `e2e/branding_tests.jac` (a cinema that chose dark)

## Context
Every theme has a light and a dark set of colours, and the storefront followed each visitor's device (P0.8b). The owner asked that the theme suggested from a logo choose light or dark itself (2026-10-19): a neon logo made for black looks wrong on a white page, a pastel or print-like logo the other way round.

## Decision
1. **`scheme` is part of the theme:** `auto` (follow the device, as before), `light` or `dark` (every visitor sees that mode). Both colour sets stay required and checked, so switching the scheme back to `auto` is always safe.
2. **Old themes keep working.** `parse_theme` treats `scheme` as optional: drafts, versions and storefronts saved before this read as `auto`. The presets and the platform default are `auto`.
3. **The model chooses it** from the logo: dark for glowing, neon, light or metallic marks or a logo with its own dark field; light for dark marks and pastel or print-like logos. Anything else it returns becomes `auto`. The random style directions no longer mention light or dark, so they never fight the logo's choice. Checked on 2026-10-19: a neon mark on black came back dark, green leaves on white came back light.
4. **The owner can change it** in Settings › Branding (Light or dark: follow each visitor's device, always light, always dark); choosing a fixed mode switches the preview to it.
5. **The storefront wears it:** `ThemeProvider(mode=...)` sets the `dark` class from the scheme and stops following the device when it is fixed. The back office keeps following the device.

## Consequences
- A cinema can show the same look to everyone, as its brand intends. Visitors who prefer the other mode don't get it on a storefront with a fixed scheme.
- While the storefront is loading (before the branding arrives), it still follows the device.
