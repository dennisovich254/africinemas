# AfriCinemas failure modes

What happens when part of AfriCinemas stops working, who it hurts, and what we do about it. The [threat model](security/threat-model.md) covers people attacking us; this covers things breaking: our servers, the services we depend on, and the cinema's own equipment. Written 2026-10-31.

**How to use it.** Every phase checks this list: a phase that touches an area updates its rows. The **pilot (17.8) doesn't start until every "Before the pilot" row is ✅.** Review the whole list every quarter, beside the restore rehearsal (`docs/runbooks/backups.md`).

**Status:** ✅ handled · ⚠️ partly · ❌ not yet. **When:** *Pilot* = before the first real cinema sells (17.8). *Scale* = before many cinemas or busy premieres. *Later* = after the pilot, if it's needed.

Several copies of the app on Kubernetes (17.3) fix only the rows about one copy or one machine failing (2.1, 2.2). Everything every copy shares (the database, a release, the region, DNS, M-Pesa) needs its own fix below.

## 1. If AfriCinemas is down: who's hurt, and how

Whatever the cause (section 2), these are the effects. Most of the fixes here work **without** AfriCinemas, so they matter even once the servers are reliable.

### Customers

| # | What goes wrong | Status | Fix | Where | When |
|---|---|---|---|---|---|
| 1.1 | **Nobody can book or pay:** storefronts, My tickets and Claude are down; sales go to other cinemas. | ❌ | A fallback page cached at Cloudflare, with a short message and AfriCinemas' support line; the status page (16.7). | 17.3, 16.7 | Pilot |
| 1.2 | **Paid, but the confirmation was lost:** M-Pesa takes the money while our server misses Safaricom's message, so the customer sees no ticket and may pay again. | ⚠️ | ✅ Their seats stay theirs while the payment is open (the sweeper never frees a paying hold), and when we're back the payment checker (`resolve_payments`) asks M-Pesa and confirms the booking; the ticket email follows. ❌ Telling customers to wait, and a second payment for the same order becomes a refund task. | 16.7, 17.6 | Pilot |
| 1.3 | **Paid during the outage, and the showtime started before we came back:** the payment becomes a refund task (money taken, nothing bought). | ⚠️ | ✅ The refund task exists. ✅ The rule is printed on the door list, with lines to write such people down (17.2). ❌ Matching them to their bookings afterwards. The rule: let in a customer with an M-Pesa confirmation SMS (our cinema's paybill, the right amount, a time before the showtime) and write its M-Pesa code and the seat on the door list; afterwards, match the code to the booking instead of refunding. ❌ Refunds are done by hand. | 17.2 (to add), 17.6 | Pilot |
| 1.4 | **Ticket emails late:** they wait and go when we're back (not lost), too late for a showtime during the outage. | ⚠️ | The ticket email isn't needed at the door when there's a door list (1.7). | 17.2 | Pilot |
| 1.5 | **Snacks bought online can't be shown or collected.** | ✅ | The door list lists each booking's snacks by pickup code, for the snack counter. | 17.2 | Pilot |
| 1.6 | **Sign-up and email confirmation links fail;** links that expire meanwhile must be sent again. | ✅ | Minor: they can be sent again. | — | — |

### At the door

| # | What goes wrong | Status | Fix | Where | When |
|---|---|---|---|---|---|
| 1.7 | **The scanner can't check tickets:** every scan asks the server, so staff can't tell a real ticket from a copy. | ⚠️ | The **door list** (17.2): every paid ticket of the showtime, printable, ticked on paper. ✅ Built, from noon the day before. ❌ Marking ticked tickets as used in one go afterwards. | 17.2 | Pilot |
| 1.8 | **The door list wasn't downloaded before the outage.** | ❌ | Email each cinema the next day's door lists every afternoon, so nobody has to remember. | 17.2 (to add) | Pilot |
| 1.9 | **The cinema's own internet is down** (not us). | ❌ | The door list (1.7) works for this too. | 17.2 | Pilot |
| 1.10 | **A scanner that works offline:** the door list is slow for a full premiere. | ❌ | The scanner downloads the showtime's tickets before doors open, checks codes on the device and sends the scans when it's back online. Needs tickets signed with a public-key signature the scanner can check (today's are signed with our secret key). | Later | Scale |

### The cinema's staff

| # | What goes wrong | Status | Fix | Where | When |
|---|---|---|---|---|---|
| 1.11 | **The box office can't sell;** staff sell on paper, and **a seat sold on paper is then sold online.** | ⚠️ | ✅ Counter seats keep seats away from online sale. ❌ A paper-selling procedure (sell only counter seats, or seats crossed off the door list), and a way to enter paper sales afterwards so they're counted and pay our fee. | 16.8, 17.2 (to add) | Pilot |
| 1.12 | **Cash can't be counted and shifts can't end;** "cash not counted" reminders fire wrongly afterwards. | ❌ | Mark an outage's time on the reconciliation, and don't remind for shifts that ended during it. | 16.8 (to add) | Scale |
| 1.13 | **The back office is down:** no scheduling, prices, cancelling or support. | ⚠️ | The status page (16.7) and AfriCinemas' support line (17.6); nothing else can help. | 16.7, 17.6 | Pilot |
| 1.14 | **Everyone is signed out after a long outage** (sign-ins last one day). | ✅ | Minor: they sign in again. | — | — |

### Money and AfriCinemas

| # | What goes wrong | Status | Fix | Where | When |
|---|---|---|---|---|---|
| 1.15 | **Billing days run out while we're down:** an invoice's 5 days to pay and 5 days' grace count days we were down, and a cinema could be reminded or flagged for not paying when it couldn't. | ❌ | Record outages; push due dates and grace periods back by them, and never send a reminder because of our own downtime. | 15.5 follow-up (to add) | Pilot |
| 1.16 | **Our fee is lost on paper sales never entered,** and the cinema's reports undercount. | ❌ | Entering paper sales afterwards (1.11). | 17.2 (to add) | Pilot |
| 1.17 | **Statements, invoices, the daily M-Pesa check and emails run late.** | ✅ | They catch up when we're back. | — | — |
| 1.18 | **Broken promises to cinemas:** the agreement mentions resilience but promises no uptime or what they get when we miss it. | ❌ | A written uptime target and what cinemas get when we miss it (owner's decision), in the cinema agreement. | 17.7 (to add) | Pilot |
| 1.19 | **Reputation:** one failed premiere night can lose a pilot cinema. | ⚠️ | Know first (2.10), tell them first (16.7: SMS or WhatsApp to every owner when an incident starts), and a write-up after (16.8). | 16.1, 16.7, 16.8 | Pilot |
| 1.20 | **Legal duties:** refunds owed to customers who paid and couldn't attend (Consumer Protection Act); an outage that is a breach (data lost, stolen or exposed) must be reported to the Data Protection Commissioner within 72 hours. | ⚠️ | ✅ Refund tasks; the breach procedure (`docs/legal/breach-procedure.md`). ❌ The incident runbooks (16.8) link to it. | 16.8 | Pilot |

## 2. What can take AfriCinemas down: the single points of failure

Each row is something that, when it fails, takes all or part of AfriCinemas down for everyone.

### Our own system

| # | What fails | Status | Fix | Where | When |
|---|---|---|---|---|---|
| 2.1 | **The app:** one copy crashes, runs out of memory, or is restarted. | ❌ | At least two copies on Kubernetes, restarted on their own, with health checks. | 17.3 | Pilot |
| 2.2 | **The machine, or its data centre zone.** | ❌ | Copies in different zones. | 17.3 | Pilot |
| 2.3 | **The database:** down, full disk, or too slow. Every copy of the app shares it. | ❌ | Managed Postgres with a hot standby and automatic failover, point-in-time recovery, disk and slow-query alerts. | 17.3, 16.1 | Pilot |
| 2.4 | **The media folder** (posters, logos, documents) is a folder on one machine, and several copies of the app can't share it. | ❌ | Object storage (Jac's S3 support) with versioning and a copy in another region. | 17.3 | Pilot |
| 2.5 | **The proxy in front** (Caddy today) on one machine. | ❌ | Cloudflare in front and Kubernetes' entrance with two copies. | 17.3 | Pilot |
| 2.6 | **A bad release or a Jac upgrade** reaches every copy at once (Jac 0.38.1 re-ran requests twice; JI-042). | ⚠️ | ✅ CI on every change. ❌ Staging first with a booking-and-paying smoke test, and a one-command rollback. | 17.4 | Pilot |
| 2.7 | **Too much traffic:** a premiere's opening. | ❌ | A load test of 500 people at once on staging, autoscaling, and the known concurrency issues (JI-038) checked under load. | 17.5 | Scale |
| 2.8 | **Background jobs** (ticket emails, payment checks, the hold sweeper) run on every copy: a job running twice could send twice. | ⚠️ | ✅ Written to be safe to run twice, and checked in (16.2). ❌ Checked under load with two copies. | 17.5 | Scale |
| 2.9 | **Losing the data:** a deleted table, a bad migration, a lost server. | ⚠️ | ✅ Nightly encrypted backups, kept 35 days, restores checked (16.5). ❌ The off-the-server copy's storage (chosen with hosting), a target for the most data we may lose and how long a restore may take, and a rehearsal by someone else. | 16.5, 17.3 | Pilot |
| 2.10 | **Nobody knows we're down:** the job that emails alerts runs inside the app, so it stops with it. | ❌ | An outside service checks the sites, `/healthz` and the certificate every minute and texts the team (16.1); error tracking (16.4). | 16.1, 16.4 | Pilot |

### Services we depend on

| # | What fails | Status | Fix | Where | When |
|---|---|---|---|---|---|
| 2.11 | **M-Pesa (Safaricom's Daraja):** no one can pay online or by M-Pesa at the counter. | ⚠️ | ✅ The console says it's likely Safaricom when failures jump across cinemas (16.3), and links Safaricom's status. ✅ Cash still works at the counter. ❌ Saying so on the storefront and status page. | 16.3, 16.7 | Pilot |
| 2.12 | **The email provider:** tickets, confirmation links and alerts don't go. | ⚠️ | ✅ Emails wait and go later. ❌ The provider (16.6, at go-live), and alerts by SMS too (16.1), not email only. | 16.6, 16.1 | Pilot |
| 2.13 | **DNS, the domain, or the certificate:** a lapsed `africinemas.co.ke` registration, a DNS mistake, or an expired wildcard certificate takes every site down at once. | ❌ | Auto-renew the domain with two people's contacts on it; the certificate's expiry watched (16.1); DNS changes only through a reviewed list. | 16.1, 17.3 (to add) | Pilot |
| 2.14 | **Cloudflare, once in front** (17.3). | ❌ | Rare and outside our control; the status page is hosted elsewhere (16.7). | 16.7 | Later |
| 2.15 | **The cloud provider or region.** | ❌ | Backups in another region (16.5, 17.3); a second region only if a cinema's contract needs it. | 17.3 | Later |
| 2.16 | **The AI provider (Gemini):** storefront designs can't be made. The booking chat is off. | ✅ | Nothing breaks: designs can be made later. | — | — |
| 2.17 | **GitHub or CI:** no fixes can be deployed during an incident. | ❌ | A documented way to deploy a release from a laptop to production in an emergency. | 17.4 (to add) | Pilot |
| 2.18 | **Jac itself:** one upstream project; an unfixed bug can block us (we've logged 60 Jac issues; #10280 is open). | ⚠️ | ✅ Version pinned, upgrades through CI, workarounds recorded (`docs/jac-issues/`). ❌ Upgrades through staging first (17.4). | 17.4 | Pilot |

### Secrets and people

| # | What fails | Status | Fix | Where | When |
|---|---|---|---|---|---|
| 2.19 | **A lost secret:** without the backup key no backup opens; without the ticket key sold tickets don't scan; without the M-Pesa key every cinema reconnects M-Pesa; without the files key verification documents can't be read. | ⚠️ | ✅ Listed in `docs/runbooks/backups.md`. ❌ A second, offline copy of each, checked whenever one changes. | 16.5, 17.4 | Pilot |
| 2.20 | **One person knows how:** the founders hold every account, secret and the know-how; if they're unreachable during an incident, nothing can be done. | ❌ | Two people for every account and secret, a rota of who's on call (16.8), and runbooks someone else has followed. | 16.8 | Pilot |
| 2.21 | **The server's clock is wrong:** holds, release times, shifts and invoices go by it. | ⚠️ | Managed hosting keeps time (NTP); check it in the health check. | 17.3 | Later |

## 3. What isn't in the plan yet

These rows say "(to add)": they need adding to the plan items named, before those are built.

- **17.2, the door list:** emailed to each cinema every afternoon (1.8); snacks on it (1.5); the rule for customers who paid during an outage (1.3); entering paper sales afterwards (1.11, 1.16).
- **16.8, the incident runbooks:** the paper-selling procedure (1.11); outage notes on the cash reconciliation (1.12).
- **15.5 follow-up:** billing due dates and grace periods pushed back by our outages (1.15).
- **17.7:** a written uptime target, and what cinemas get when we miss it (1.18), the owner's decision.
- **17.4:** an emergency deploy without GitHub (2.17); offline copies of the secrets (2.19).
- **17.3:** auto-renewing the domain, with two contacts (2.13).
