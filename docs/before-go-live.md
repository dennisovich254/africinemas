# Before going live: what couldn't be tested by hand yet

Started 2026-10-28 and covering the whole application, Phases 0 to 15. Revisit every
item before the first real cinema sells, and tick it once it's been tried on staging or
live.

There are two parts:
- **Part 1: built, but not tried for real.** These work in automated tests, but depend
  on something a laptop doesn't have: Safaricom, real email, real domains, real phones,
  the AI models, several servers, or time passing.
- **Part 2: not built yet, but needed before going live.** Each one points to where it's
  planned.

Locally, anything that only needs days to pass can be tried with a shifted clock:
`faketime -f "+Nd" jac run --dev main.jac`. That covers overdue invoices, reminders,
suspension, the fee rule's future dates and retention, so they're only listed where
something else is missing too.

---

# Part 1: built, but not tried for real

## M-Pesa: customers paying for bookings (Phase 5, 6.5, 12.7, 12.10, 12.14)

Locally every payment goes through the simulator (`AFRICINEMAS_PAYMENTS=simulator`).
The Daraja sandbox run (5.7, `docs/runbooks/daraja-sandbox.md`) uses Safaricom's test
system, not real money.

- [ ] **A real customer pays online** with live Daraja. The prompt arrives, the PIN is
  entered, the money reaches the cinema's own paybill, and the tickets are issued.
- [ ] **Safaricom's callbacks reach us**: `DARAJA_CALLBACK_BASE` is the public https
  address, and `/hooks/mpesa/{token}` receives them through any firewall or proxy.
- [ ] **Real failures**: a customer with too little money, a wrong PIN, a cancelled
  prompt, a phone that's off, an expired prompt. The simulator scripts these by phone
  number; real result codes and timings may differ.
- [ ] **The resolver with a really stuck payment** (5.5): no callback arrives, and
  Daraja's status query settles it later.
- [ ] **Money taken but nothing bought** (a payment after the hold expired, a second
  payment, a different amount) creates a refund task. Check the box office knows what
  to do with one: there's no refund screen yet (Part 2).
- [ ] **M-Pesa at the box office** (6.5, 12.10): the customer's own phone gets the
  prompt at the counter, and the sale completes.
- [ ] **More snacks after booking** (12.14), paid separately, on live M-Pesa.
- [ ] **Holds and payment timing on slow phones and networks**: the hold is extended
  while paying (5.3). Check it doesn't run out on a slow 3G connection.

## Each cinema's own M-Pesa (P15.3)

- [ ] **A cinema connects its own live Daraja app**: real consumer key, secret, passkey
  and shortcode, from Safaricom's production portal rather than the sandbox.
- [ ] **The KES 1 test payment** reaches the cinema's own paybill or till, and the
  prompt on the owner's phone shows the business's real registered name. The name check
  only compares what the owner typed, because Daraja can't look a paybill's name up.
- [ ] **A Till** (Buy Goods) pays the till number, signed with the store number.
- [ ] **Customers' payments go to each cinema's own paybill**, and each is checked with
  that cinema's keys. Locally the simulator records this; live, check each cinema's
  M-Pesa statement.
- [ ] **A change of paybill waits its 24 hours** in real time and then takes over, while
  payments in flight still settle with the old account.
- [ ] **The setup video** (a real AfriCinemas recording, its link set in the console)
  plays on phones and desktops, and booking a setup call reaches whoever answers Help.
- [ ] **`AFRICINEMAS_MPESA_KEY` is backed up** with the deployment secrets, and a
  restore on a new server still opens the cinemas' sealed keys. Losing it means every
  cinema connects again.

## AfriCinemas' own paybill: invoices (P15.4, P15.5)

- [ ] **AfriCinemas' live paybill exists** and `AFRICINEMAS_BILLING_PAYBILL` is set to
  it. Until then statements show the placeholder 000000 and say payments are tests.
- [ ] **`DARAJA_SHORTCODE` and the `DARAJA_*` keys are AfriCinemas' own live app for
  that same paybill.** Pay now sends invoice prompts through it.
- [ ] **Pay now for real**: an owner pays an invoice from Billing, the money arrives in
  AfriCinemas' paybill with the invoice number as the account, and the invoice reads Paid.
- [ ] **Rounding to whole shillings**: a KES 49.80 invoice is paid as KES 50. Confirm the
  accountant is happy with the rounding line, or switch to rounding down.
- [ ] **The unmatched-payments list** (a payment for an invoice already paid or waived,
  or for another amount). Matching by hand and recording a refund are tested
  in-process only: the simulator can't produce one by hand. Try one on staging with
  two real prompts.
- [ ] **Refunding an unmatched payment** is done outside the app (M-Pesa reversal or a
  transfer). Agree who does it and how it's recorded.

## Staff emails (ADR-0087)

- [ ] **Staff can't start a shift until they confirm their email.** The confirmation
  email must reach new staff as soon as they join, from the live email provider. Try it
  with a real invite on staging before inviting a cinema's team.

## Reconciliation (P15.6)

- [ ] **The daily M-Pesa check against live Daraja**: the STK status query still answers
  for prompts a day or more old. If it doesn't, those payments are left unchecked.
- [ ] **A real M-Pesa portal statement** (CSV) uploads and matches: check its column
  names (Receipt No., Completion Time, Paid In, Transaction Status, A/C No.), its time
  format, and how it shows the KES 1 test payments.
- [ ] **Cash counts in practice**: the box office counts at the end of each shift, and a
  manager looks at the Reconciliation page. Agree who resolves a short count.

## The monthly billing job, in real time (P15.4)

- [ ] **Statements go out on the 1st by themselves**, from the hourly job, without
  pressing *Issue what's due now*. Locally `AFRICINEMAS_BILLING_EARLY` was used instead.
  Production must never set it.
- [ ] **A cinema in another time zone** gets its statement on its own 1st, with its own
  local days.
- [ ] **Invoice numbers stay in order** over months on the real database (AC000001,
  AC000002, …). A server stopping mid-issue can leave a gap. Check that's acceptable
  for KRA.

## Emails: every one of them (P6.3, P13.5, P14.2, P14.5, P15.3, P15.5, P16.6)

There's no email provider yet. Every email is written to the development outbox
(`.jac/outbox`), so none has been received in a real inbox.

- [ ] **Ticket emails** with their QR codes (P6.3) arrive, the QR images show in Gmail,
  Outlook and phone mail apps, and the codes scan at the door.
- [ ] **Resending tickets** (6.3) and the **My tickets** links in them work.
- [ ] **Email confirmation links** (P14.2) arrive and confirm.
- [ ] **Staff invitations** reach the person invited (2.5), and so does the platform's
  join link (13.1, `scripts/platform_setup.sh`).
- [ ] **Support replies** (13.5) reach the cinema's owners.
- [ ] **Verification decisions** (14.5a) reach the owner.
- [ ] **M-Pesa connection and change warnings** (15.3) reach every owner.
- [ ] **Billing emails** (15.5): invoice paid, reminders, dispute answers, suspended,
  reinstated.
- [ ] **Nothing lands in spam**: SPF, DKIM and DMARC are set for the sending domain
  (16.6).
- [ ] **Owners with no email on their staff record** get nothing. Check every live
  cinema's owners have one.

## The three sites and real addresses (P13.1b, `docs/runbooks/three-sites.md`)

Locally everything is on `localhost` (with `admin.localhost` and `<slug>.localhost`).

- [ ] **The real domains**: `africinemas.co.ke` (the back office and landing page),
  `admin.africinemas.co.ke` (the console), and `<slug>.africinemas.co.ke` (every
  storefront), with wildcard DNS and a wildcard TLS certificate.
- [ ] **A new cinema's storefront address works at once**, with no DNS change.
- [ ] **Links in emails and from Claude** use each cinema's own address
  (`AFRICINEMAS_PUBLIC_URL`, `AFRICINEMAS_SITE_DOMAIN`).
- [ ] **Signing in stays per site**: a back-office sign-in isn't a console sign-in, and
  a customer's account belongs to its cinema (ADR-0009).

## Real phones and real places

- [ ] **The ticket scanner** (6.4) on real phones (Android and iPhone): camera
  permission, focus in a dark foyer, a cracked or dim screen, and the manual entry
  fallback.
- [ ] **The snack counter's pickup scanner** (12.9), likewise.
- [ ] **The storefront on low-end Android phones** and slow networks: the seat map,
  checkout and the countdown.
- [ ] **The back office on a phone** for owners who never use a computer.
- [ ] **Trailers** (YouTube privacy-enhanced, Vimeo) play once Play is pressed, and set
  nothing before then (the cookie notice).

## The AI features (Phase 8, branding)

In tests every AI answer comes from a script, never a real model
(`AFRICINEMAS_AGENT_SCRIPT`, `AFRICINEMAS_KIT_PLAN`, `AFRICINEMAS_PAGE_SCRIPT`).

- [ ] **The booking chat** (8.4, 8.5) with the real model. It's switched **off** in
  production for now (`core/agent/switch.jac`); if it's turned on, check the answers,
  the cost per conversation, and the daily limits.
- [ ] **Booking from Claude** (8.6): the MCP server and OAuth sign-in from a real Claude
  connector against the public address.
- [ ] **Design my storefront / the brand kit** (ADR-0046 to ADR-0049) with the real
  model and a real cinema's logo: colours, fonts and the page it writes.
- [ ] **The storefront page review from screenshots** (ADR-0050) needs a headless
  browser on the production server: `python -m playwright install --with-deps
  chromium-headless-shell`.
- [ ] **Theme suggestions from a logo** (ADR-0043), with the real key (`GEMINI_API_KEY`
  or `ANTHROPIC_API_KEY`, whichever that feature uses).
- [ ] **The server can reach the AI providers.** This machine's IPv6 route to Google
  broke once (2026-10-19). Check the production server's network.
- [ ] **Keys and spending limits** are set on the providers' dashboards.

## Several servers, real load and real data

- [ ] **More than one server copy** (`jac scale deploy`): the claims keep each slug,
  seat hold, ticket, M-Pesa receipt, statement, invoice number and reminder unique.
  They're tested in-process and in the load test (4.7), not on the real deployment.
- [ ] **Background jobs on every copy**: the hold sweeper, payment resolver, settling,
  emails, retention and billing each do their work once.
- [ ] **A busy release** (a blockbuster's first showing): many customers holding seats
  at once on the real server, not only the in-process load test.
- [ ] **Posters, documents and uploads survive a restart and a redeploy**
  (`AFRICINEMAS_MEDIA_DIR` on persistent storage).

## Production settings

- [ ] **`deploy/production.env` is what the live server runs with**: `/docs` and
  `/graph` off, Jac's built-in admin not created, short token lifetimes, body limits.
  `tests/integration/production_server_tests.jac` checks this in-process only.
- [ ] **Every secret is set and backed up**: `JAC_SERVE_AUTH_SECRET`, `JAC_DB_URL`,
  `AFRICINEMAS_TICKET_KEY`, `AFRICINEMAS_MPESA_KEY`, the SMTP password, the Daraja keys,
  and the AI keys.
- [ ] **No test-only setting is set**: `AFRICINEMAS_BILLING_EARLY`,
  `AFRICINEMAS_CLOCK_CONTROL`, `AFRICINEMAS_AGENT_SCRIPT`, `AFRICINEMAS_KIT_PLAN`,
  `AFRICINEMAS_PAGE_SCRIPT`, or `AFRICINEMAS_PAYMENTS=simulator`.
- [ ] **The platform's super admins** (`AFRICINEMAS_PLATFORM_ADMINS`) each join with
  their own password.

## Trust, verification and retention (Phase 14)

- [ ] **A real verification**: a real owner's ID photos and real business documents
  (registration certificate, KRA PIN certificate, county permit) uploaded, reviewed and
  approved, on a phone camera too.
- [ ] **Retention deletes for real** after 90 days and a year (14.5b), on the production
  server, and the files are really gone from storage and backups.
- [ ] **The Verified badge and `/verified`** look right on a live storefront.

## Tax, legal and records (P15.0, P15.4)

- [ ] **The advocate's review** of every legal document. Today they're published as
  version 0.1, before review (ADR-0078).
- [ ] **The registrations checklist** in the console is really done: company, KRA PIN,
  ODPC, paybill, county permit and the rest. They're ticked by hand, outside the app.
- [ ] **VAT**: ticking VAT on the registrations checklist adds 16% to new statements.
  Confirm the rate, and whether VAT is charged before or after a credit brought forward,
  with the accountant once AfriCinemas registers.
- [ ] **The PDF's wording and layout** suit an invoice under Kenyan rules: AfriCinemas'
  KRA PIN, address and the cinema's PIN may need to be on it.
- [ ] **Accepting a new version of the cinema agreement** (15.1) is tried with a real
  owner, and sales pause until they do.

## Screens with no browser test yet

- [ ] **Amounts below zero in the back office** (refunds, fee credits) read `-KES 150.50`.
  No screen can make a refund yet, so this hasn't been seen in a browser.
- [ ] **The Issue, dispute and match buttons are hidden** for platform staff who can't
  use them (reviewers, support). The server refuses them, but no browser test signs
  in as a reviewer.

## Decisions to confirm

- [ ] **Who may suspend a cinema**: today anyone with `platform.suspend`, which includes
  reviewers as well as super admins. The plan said super admins.
- [ ] **Who may pay an invoice**: anyone who reads the cinema's financial reports
  (owner, general and finance managers, auditors). Check auditors should be able to.

---

# Part 2: not built yet, but needed before going live

These are in the plan already. They're listed here so nothing is forgotten. Some of
them, such as monitoring and backups, are what make testing Part 1 safe.

## Money

- [ ] **Paying an invoice by hand at the paybill (C2B)** (P15.5 follow-up): Daraja's C2B
  confirmation and validation URLs registered on AfriCinemas' paybill, then matched to
  the invoice or sent to the unmatched list.
- [ ] **A refund screen** (P15.2 follow-up): refunds and their fee credits exist only on
  the server (`record_refund`).
- [ ] **The fee on each order's page** (P15.2 follow-up, P17.1).
- [ ] **Credit notes** (P15.4 follow-up): a correction to an issued invoice.
- [ ] **eTIMS**: invoices submitted to KRA, once AfriCinemas registers.
- [ ] **Every transaction in the back office** (P17.1) and **finding a booking** (P6.6),
  so the box office can answer "I paid".

## Operations (Phase 16)

- [ ] **Uptime checks and alerts** (16.1).
- [ ] **Job check-ins** (16.2).
- [ ] **M-Pesa failures across the platform** (16.3).
- [ ] **Error tracking** (16.4).
- [ ] **Backups, and a restore rehearsed** (16.5).
- [ ] **A real email provider** (16.6).
- [ ] **A status page** (16.7).
- [ ] **Incident runbooks and on-call** (16.8).

## Production and hardening (Phase 11, folded into Phase 17)

- [ ] **The security pass** (11.1): the full isolation suite, production-config checks.
- [ ] **The claim reconciliation job** (11.1b).
- [ ] **Faster holds under load** (11.1c).
- [ ] **Deployment** (11.2).
- [ ] **Demo data** (11.3) and **docs** (11.4).
- [ ] The rest of **Phase 17** (resilience, the pilot).

## Legal and privacy (from `docs/legal/README.md`)

- [ ] **The confirmation email names the version of the terms agreed**, with a link.
- [ ] **A test that every browser-storage key is listed** in the cookie notice.
- [ ] **The KFCB rating wherever a film is listed**: every listing, card, chat card and email.
- [ ] **An 18-or-over declaration** at sign-up and payment.
- [ ] **The verification page's guidance** on what not to upload (family details).
- [ ] **Verification files encrypted at rest**, and the owner emailed when they're
  viewed or changed.
- [ ] **Customers' "Download my data" and "Delete my account"**.
- [ ] **A requests register and a breach register** in the console.
- [ ] **Where data is stored** (P17.3): verification files in Kenya or a permitted country.

## The platform console

- [ ] **Platform staff and roles** (13.1): still open in the plan; check what's left.

## After the pilot (owner, 2026-10-24): not needed to go live

- The desktop app (Phase 9).
- The mobile app (Phase 10).
- Snacks in the chat and in Claude (12.12).
- Storefront structure, tier B (4.1e).
