# ADR-0062: Help requests: emails to owners, and screenshots

- **Status:** Accepted
- **Date:** 2026-10-23
- **Sub-phase:** P13.5b
- **Code:** `core/support/mail.jac`, `core/support/requests.jac` (screenshots, `REPLY_MAIL`, `owner_emails`), `core/catalog/poster.jac` (`decode_screenshot`, `process_screenshot`), `web/support/SupportThread.jac` (`ChatImage`, the composer's paperclip)
- **Tests:** `tests/integration/support_tests.jac`, `e2e/support_tests.jac`

## Context
A cinema that asks for help shouldn't have to keep its back office open to learn that we've answered. Many problems are also easiest to show: a screen with an error, an M-Pesa message.

## Decision
1. **Our reply emails the cinema's owners, one email each, and nobody else.** Owners are the active staff with the owner role and a sign-in email.
   - It's queued, not sent inside the request, using the same machinery as the ticket email (ADR-0022): a claim per email, a job every few seconds, a failed send kept for the next run, and one sender at a time.
   - It says what the request is about, quotes our latest message (escaped in the HTML), and links to the conversation in the back office. It carries no screenshot.
   - A cinema's own messages email nobody.
2. **A message can carry one screenshot**, from either side. A message can be a screenshot alone.
   - **Upload:** JPEG, PNG or WebP, up to 3 MB. With base64, that still fits under the server's 5 MB request limit, where 5 MB posters wouldn't.
   - **Checks:** the same as posters (§56): the type must match the file's own bytes, the size is capped before decoding, and the picture is re-encoded as a fresh WebP of at most 1920 px, so nothing in the file but its pixels is kept.
   - **Storage:** in the cinema's own media folder, under a name of ours.
3. **Only the cinema and our support team read a screenshot.**
   - The cinema reads its own through `support_image`. Our support staff read them through `platform_support_image` (`platform.support`).
   - The pages only learn that a message has one (`has_image`), never where it's kept.
   - In the chat, a screenshot shows inside its message bubble, and opens full size in a new tab.

## Consequences
- A screenshot may show a customer's details on the cinema's screen. It stays the cinema's, and only our support reads it, as with anything a cinema writes in a request (ADR-0061).
- Screenshots aren't deleted when a request is closed. Retention belongs to the document-retention decision due at 14.4 (owner, 2026-10-22).
