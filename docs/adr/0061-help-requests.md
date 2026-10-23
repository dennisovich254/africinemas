# ADR-0061: Cinemas' help requests, and AfriCinemas' support inbox

- **Status:** Accepted
- **Date:** 2026-10-23
- **Sub-phase:** P13.5a
- **Code:** `core/support/requests.jac`, `core/authz/policy.jac` (`support.request`), `web/backoffice/HelpSection.jac`, `web/platform/SupportPages.jac`, `web/support/SupportThread.jac`
- **Tests:** `tests/integration/support_tests.jac`, `tests/unit/authz_tests.jac`, `e2e/support_tests.jac`

## Context
AfriCinemas supports cinemas with technical problems, not cinemas' customers (Phase 13, owner decision 2026-10-22). A cinema needs one place to tell us something isn't working and to read our answer, and our support staff need one inbox for every cinema.

## Decision
1. **A request is the cinema's own record.** It's a `SupportRequest` node on its Tenant, owned by its principal, like a staff invitation. It has a category (payments and M-Pesa, emails, storefront, verification, something else), a status and a thread of messages. Other cinemas can't see it. We read it through the system root, as the directory reads cinemas.
2. **Who asks:** staff with the new `support.request` permission. That's owners, tenant admins, and general and finance managers: the people who meet technical problems and can describe them. Box office staff and ushers ask their manager. Asking needs an open shift, like every cinema action.
3. **Who answers:** platform staff with `platform.support` (support and super admins) read every cinema's requests, reply, and close or reopen them. Reviewers don't.
4. **The status says whose turn it is.**
   - **Open:** our turn. That's a new request, or one where the cinema wrote last.
   - **Waiting for the cinema:** we replied.
   - **Closed:** either side closed it. A reply reopens it.

   The inbox shows one status at a time, Open first, each with its count. The cinema sees the same statuses from its side: "Waiting for AfriCinemas", "AfriCinemas replied", "Closed".
5. **Each side's actions go to its own audit log.** The cinema's requests and replies go to the cinema's. Our replies, closes and reopens go to the platform's, recorded as being about the cinema, so they show in its history in the directory (ADR-0059).
6. **Who wrote what:** the cinema sees "You" for its staff (with their email) and "AfriCinemas" for us, never which of us. We see the cinema's name and its staff member's email, and our own team's emails.
7. **It's laid out like a messaging app** (owner, 2026-10-23: "like a normal chat, like WhatsApp").
   - The cinema's Help is a list of conversations: each one's topic, last message and status, plus "New request". A conversation opens as a chat at `/app/<slug>/help/<id>`.
   - In the chat, the reader's own messages are on the right in the accent colour and the other side's on the left, each with its time. The message box is at the bottom: Enter sends, Shift+Enter starts a new line.
   - Our side, a request's page in the console, is the same chat, with Close or Reopen at the top.
8. **Live without a refresh, by asking every few seconds** (owner, 2026-10-23). An open chat asks every 5 seconds, and the lists and the sidebar's counts every 30 seconds. A tab in the background asks nothing and catches up when it's back.
   - Help's link counts the conversations AfriCinemas has answered. Support's link counts the requests waiting on us.
   - Not WebSockets: Jac's can answer the sender or broadcast to everyone, but can't reach one cinema's staff (JI-054), and a broadcast of a private message would leak it.
9. **We see only what a cinema writes.** Support has no way into a cinema's bookings or customers. The form says never to include passwords, PINs or card numbers.

## Consequences
- **13.5b** emails the cinema when we reply, and lets a request include a screenshot.
- **13.5c** adds per-cinema health signals beside the inbox: payments needing attention, M-Pesa errors, failed emails and stuck orders.
- The inbox reads every cinema's requests on each visit, like the directory (ADR-0058). That's fine for hundreds of cinemas.
