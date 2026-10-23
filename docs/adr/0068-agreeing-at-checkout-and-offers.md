# ADR-0068: Paying is agreeing to the policies; offers only when the customer asks

- **Status:** Accepted
- **Date:** 2026-10-24
- **Sub-phase:** P14.3c
- **Code:** `web/storefront/AgreeNotice.jac`, `web/storefront/PayPanel.jac`, `web/storefront/CustomerAuthPages.jac`, `web/storefront/AccountPage.jac` (`OffersSetting`), `core/payments/payment_api.jac` (`start_payment`'s `offers`, `Order.terms_shown`), `core/catalog/policies.jac` (`shown_at_checkout`, `public_policies`), `core/notify/offer_consent.jac`, `core/catalog/site_info.jac` (`sends_offers`)
- **Tests:** `tests/integration/checkout_consent_tests.jac`, `tests/unit/site_info_tests.jac`, `tests/isolation/registry.jac`, `e2e/checkout_consent_tests.jac`

## Context
14.3b let cinemas publish their terms, refunds and privacy policies. A customer has to agree to them when buying, and the cinema may need to show later what was agreed. Separately, Kenya's Data Protection Act, 2019 lets a cinema send offers only to people who opted in, and asks it to be able to prove that they did.

## Decision
1. **A notice above Pay, no tick box for the terms.** The notice reads: "By paying, you agree to this cinema's terms of ticket sale and refund policy. Its privacy policy says how your details are used."
   - Each policy is a link that opens in a new tab, so the checkout isn't lost.
   - Paying is the agreement, and the notice sits beside the button the customer presses. A tick box would add a step without adding consent.
   - The notice names only the published policies. A live cinema has all three (14.4 requires them).
   - Creating an account says the same, with "By creating an account".
2. **The order keeps what was shown.** When an online payment starts, the order records the `updated_at` of each policy the notice linked to (`terms_shown`). A later change doesn't alter it, so a disputed refund can be checked against the version the customer agreed to. Box office sales record nothing: staff sell there, and the customer agrees to nothing online.
3. **Offers: one box, never ticked for the customer.** It shows at checkout and sign-up only when the cinema says, in Website information, that it sends offers.
   - **When it's recorded:** only when ticked, for the email address that pays or signs up.
   - **What's kept:** when consent was given, where (checkout, sign-up or account) and the order's reference.
   - **Changing it:** a signed-in customer turns it off or on in My account. Withdrawing keeps the record, marked with when they stopped, as proof that we did.
   - **Where it lives:** a permanent claim per cinema and email, like saved bookings and email confirmations. We first kept it as a graph node made while the payment started, after the payment's commit, and the node wasn't kept. We didn't find out why, and claims are simpler for this anyway.
4. **No sending yet.** Nothing sends offers today. These records are what a later "email your customers" feature must check first.

## Consequences
- **Guests:** a guest who opted in at checkout can only stop offers by signing up with that email, or, once offers are sent, through the unsubscribe link every such email must carry.
- **Policy versions:** `terms_shown` names versions by their `updated_at`. Older texts aren't kept yet, so showing the exact wording of an old version needs policy history (later).
