# ADR-0067: A cinema's policies, written in the app from our templates

- **Status:** Accepted
- **Date:** 2026-10-24
- **Sub-phase:** P14.3b
- **Code:** `core/catalog/policies.jac`, `core/theming/branding_api.jac` (`public_branding` lists the published ones), `web/backoffice/PoliciesSection.jac`, `web/storefront/PolicyPage.jac`, `web/storefront/FooterInfo.jac`, `web/AppRoot.jac`
- **Tests:** `tests/unit/policies_tests.jac`, `tests/integration/policies_tests.jac`, `tests/isolation/registry.jac`, `e2e/policies_tests.jac`

## Context
Every cinema booking site must publish its terms of sale, privacy policy and refund policy, and should explain its house rules, accessibility and the age ratings (the list agreed on 2026-10-22). Most of our cinemas won't have these written. Some will have them as PDFs from a lawyer.

## Decision
1. **Six policies, one record per cinema.** A `Policies` node owned by the cinema holds each kind's text, whether it's published, and when it was last saved. The kinds are terms, privacy, refunds, house rules, accessibility and age ratings. They're edited in **Settings → Policies** by staff who may change the cinema's settings, and each save is in the cinema's audit log (`policy.saved`).
2. **Our templates are a starting point, not advice.** Each kind has a plain-language template, made for Kenya, with the cinema's business name and contact (from 14.3a) filled in:
   - **privacy** follows the Data Protection Act, 2019, and names AfriCinemas and Safaricom as the processors;
   - **age ratings** explains the KFCB classes.

   The cinema starts from it or writes its own. Publishing needs a tick that the writer has read it and it's right for their cinema, so we never publish our words on a cinema's behalf unread.
3. **A small plain format, drawn as text.** Policies are long and need structure. Rather than HTML or Markdown, the format is:
   - a blank line between paragraphs;
   - `## ` to start a heading;
   - `- ` to start a list item.

   The storefront and the editor's preview draw it as React text (`PolicyText`), so nothing typed can become markup, and no HTML is stored. Control characters are dropped, and each policy is limited to 20,000 characters.
4. **Drafts stay private.** Only a published policy reaches the storefront: `public_policy(slug, kind)`, for a public cinema only (ADR-0064), and the footer's links from `public_branding`. Unpublishing takes it down at once.
5. **Required: terms, privacy and refunds.** `missing_policies(cinema)` names those not yet published, for 14.4's "Submit for review".
6. **The pages:** `/policies/<kind>` on the cinema's own address, and `/c/<slug>/policies/<kind>` on the others. Each shows its title and when it was last updated.

## Consequences
- **PDFs come later.** A policy as an uploaded PDF, and public documents such as licences, need checked uploads; they come in 14.3d. A published written policy stays the way the footer links to it.
- **Editing a template doesn't change published policies.** A cinema that started from one keeps its own copy.
- **Showing the terms at checkout** ("By paying you agree to…") is left for a later sub-phase.
