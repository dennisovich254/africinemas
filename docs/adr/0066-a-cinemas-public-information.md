# ADR-0066: A cinema's public information, in a footer no design can leave it out of

- **Status:** Accepted
- **Date:** 2026-10-23
- **Sub-phase:** P14.3a
- **Code:** `core/catalog/site_info.jac`, `core/theming/branding_api.jac` (`public_branding` carries it), `web/backoffice/SiteInfoSection.jac`, `web/storefront/FooterInfo.jac`, `web/storefront/AiPage.jac` (`AiPart`'s `inside`), `web/storefront/site_info_view.jac`, `web/storefront/StorefrontShell.jac`
- **Tests:** `tests/unit/site_info_tests.jac`, `tests/integration/site_info_tests.jac`, `tests/isolation/registry.jac`, `e2e/site_info_tests.jac`

## Context
Every cinema booking site must say who runs it and how to reach them (the list agreed on 2026-10-22). A cinema's storefront may be an AI-written design (ADR-0046 to ADR-0050), which we don't control line by line, so anything required can't be left to the design.

## Decision
1. **One record per cinema.** A `SiteInfo` node, owned by the cinema like its other settings. It holds the business name and address, the support phone, email, WhatsApp number and hours, social media handles, directions and parking, booking notes (up to 10, a ticket type and what it means) and a payment note. It's edited in **Settings → Website information** by staff who may change the cinema's settings (`tenant.settings.update`), and every save is in the cinema's audit log (`site_info.saved`).
2. **Plain text, checked on the server, every problem at once.**
   - **Markup:** nothing with `<` or `>` is kept, as on the home page (§41). Each text has a length limit.
   - **Numbers:** phone and WhatsApp must be Kenyan numbers and are kept as `+254…`.
   - **Email:** checked for its shape.
   - **Refusals:** a refused save names each field with a problem (`invalid_info`, with `problems`), and the form shows each problem beside its field.
3. **Links are built by us, never taken as typed.** Social media is saved as handles (a leading `@` is dropped; a pasted address is refused, with a hint to type the name only). The storefront gets links to the network itself (`https://www.instagram.com/<handle>`…), and WhatsApp becomes `https://wa.me/254…`. So a field can't point visitors to an arbitrary site.
4. **Served with the storefront's branding.** `public_branding` carries the public view (`info`), so every page has it with no extra request. `public_site_info(slug)` serves it alone. Both answer only for a cinema that's public (ADR-0064).
5. **In the footer, put there by us, not the design.** `StorefrontShell` draws `FooterInfo` inside the footer of every storefront page: in our own footer, above its bottom row ("Tickets by AfriCinemas"), and in an AI-written design as the last child of the AI's own `<footer>` (`AiPart`'s `inside`), so it sits on the design's background and takes its text colour. It shows the business, the contact and the socials. We first drew it as a separate strip under the footer; the owner saw two footers and asked for one (2026-10-24). The AI's footer must already say "Tickets by AfriCinemas" (core/theming/pagecode.jac), so we don't add it there. 14.3b adds the policy and document links, and 14.6 adds "Report this cinema". "Getting here" (directions and parking) shows on the Cinemas page, and "Good to know" (booking notes, how to pay) on the showtime page before choosing tickets.

## Consequences
- An empty field shows nothing, so a cinema that hasn't filled this in shows nothing extra in its footer. Making some fields required belongs to submitting for review (14.4).
- New networks need a URL template in `SOCIALS`; a handle that doesn't fit `HANDLE_PATTERN` is refused, not guessed at.
