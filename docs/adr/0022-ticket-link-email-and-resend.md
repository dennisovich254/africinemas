# ADR-0022: Tickets reach the customer by a private link and a queued email, resendable three times an hour

- **Status:** Accepted
- **Date:** 2026-10-07
- **Sub-phase:** P6.3a
- **Code:** `core/booking/ticket_delivery.jac`, `core/booking/ticket_codes.jac` (`link_token`, `link_key`), `core/notify/` (`addresses`, `mailer`, `ticket_mail`), `core/payments/payment_api.jac` (email), `core/payments/settlement.jac` (link and mail at finalize), `web/storefront/TicketDelivery.jac`, `web/storefront/TicketsPage.jac`
- **Tests:** `tests/unit/mail_tests.jac`, `tests/unit/ticket_code_tests.jac`, `tests/integration/ticket_mail_tests.jac`, `e2e/payment_tests.jac`

## Context
ADR-0010 settled guest checkout: the buyer gives an email address, gets the tickets on screen and by email, and gets back to them later with a booking secret stored only as a hash. Mail goes from one AfriCinemas sender, with the cinema's name and its Reply-To. Visitors are anonymous, and the browser's holder id lasts only as long as the tab, so without a link the tickets are lost once the tab closes. Jac's built-in emailer can't set Reply-To or carry images (jaseci-labs/jac#9847 proposes both).

## Decision
1. **The email at checkout.** `start_payment` requires an address (checked as the pay form checks it) and stores it on the order with the payment, in the same commit.
2. **The private link** is `/c/<slug>/tickets/<token>`.
   - The token is an HMAC over the cinema and order with the ticket key (128 bits, lower-case base32). It can be made again for the email and the paying visitor's page, so it is never stored.
   - The claim `order-link` maps the token's SHA-256 hash to the order. Settling claims it provisionally, then makes it permanent after the finalize commit.
   - `tickets_by_link` (public) shows the booking: the movie, the showtime, where, the masked address and the QR cards. A wrong token, another cinema's, or an unpaid order all answer `not_found`, alike.
3. **The ticket email is queued, never sent inside a request.**
   - Finalize queues one claim per email (`ticket-mail`, value `<tenant>|<order>|<address>`). The `send_ticket_mail` job sends them every `AFRICINEMAS_MAIL_SECONDS` (5).
   - A failed send stays queued for the next run. A short `ticket-mail-sending` claim keeps two servers from sending the same email.
   - **Sender:** the cinema's name on `AFRICINEMAS_MAIL_FROM`, with Reply-To the contact email from the cinema's published home page, if any.
   - **Content:** one QR PNG per seat inside the HTML (`cid:`, made with `segno`), the references, the showtime in the cinema's time zone and the link, in both text and HTML.
4. **Sending.**
   - **With `AFRICINEMAS_SMTP_HOST`:** SMTP through Python's standard library (STARTTLS, optional login).
   - **Without it:** the development outbox, one `.eml` file per message (`AFRICINEMAS_OUTBOX_DIR`, default `.jac/outbox`), kept in memory for tests. Nothing leaves the machine.
5. **Resending.** `resend_tickets` (public, authorized by the link) queues the email again, to the order's address or a corrected one, which then becomes the order's.
   - The limit is three an hour per order: each resend takes one of three hour-long claims.
   - Past the limit it answers `too_many_resends` with `retry_after_s`.

## Consequences
- **Production needs SMTP settings** with SPF, DKIM and DMARC on our domain (ADR-0010), plus `AFRICINEMAS_PUBLIC_URL` for links in emails.
- **Rotating the ticket key** changes every link and QR code. Old links then answer `not_found`.
- **"My tickets" for signed-in customers** (6.3b) builds on the same link: "save to my account" proves the link.
- **When Jac's emailer gains Reply-To and attachments,** `core/notify/mailer.jac` can send through it instead.
