# Specification: the offline scanner (plan 17.2b)

**Version 2, 2026-10-31.** Agreed decisions O1–O5 (owner, 2026-10-31). Needed **before the pilot**. Closes failure modes 1.7, 1.9 and 1.10 (`docs/failure-modes.md`).

**Changes from version 1:** an outside review (2026-10-31), checked against the code, found the gaps were in the moves between online and offline. Version 2 adds:
- a scan id on **online** scans too;
- crash-safe rules on the device and the server;
- an offline start-up path that needs no server, with our own manifest;
- an **offline grant** separate from the sign-in;
- a real **sync protocol**;
- receipts that can admit a group;
- a **scan journal** separate from ticket state;
- a field-by-field data inventory, versions, and guarantees that say when they hold.

It also corrects four details: showtime states, the order of checks, the Android version, and two over-strong claims.

**How to read it:** rules marked **MUST** are the ones the pilot depends on. Each has an id (R1, R2…), and §20 tests every one.

## 1. Why

Today every scan asks the server whether the ticket is real, for this showtime, and unused (`core/booking/redeem_api.jac`). If AfriCinemas is down, or the cinema's own internet is, the scanner can't answer. The door list (17.2) is the paper fallback, but it's out of date the moment it's made, and many tickets are bought on the day. The offline scanner keeps checking tickets against a copy kept on the device, which stays up to date while the device can reach us.

## 2. Goals, and when they hold

1. **Same answers where it can know.** Offline, the scanner gives the online answers for every ticket in its copy (§9.4). It can't know about sales, refunds, scans on other devices or revoked access it hasn't synced; the screen shows how old its copy is.
2. **Fresh while active.** While the scanner is open, authorized and syncing successfully, the device MUST apply committed changes within **60 seconds**, and MUST show when it last *applied* a sync (R1). A phone that suspends the page can't be held to this, so the age is always on screen.
3. **No admission lost once committed.** Every admission committed on the device MUST stay pending until the server acknowledges it durably (R2). Recovery needs the device's storage to survive and an authorized way to upload; a lost or wiped device loses what it hadn't uploaded.
4. **Problems found afterwards.** Double entries, admissions of refunded tickets, and people let in anyway are found after reconnecting and shown to managers (§11.4).
5. **Little on the device.** No customer details, and nothing that can make a ticket (§16).
6. **The phones cinemas have.** Android 10+ with current Chrome first; iPhones with iOS 16.4+, installed to the home screen (O4).

**Not in scope** (later, if needed):
- selling at the box office offline (17.2, part 4: paper sales);
- devices talking to each other;
- a native app (18.1);
- snack pickup codes offline (O3: after the pilot);
- changing how tickets are signed.

## 3. When it's used

| Situation | What happens |
|---|---|
| Everything works | Scans go to the server as today, each with a scan id. The device keeps its copy up to date. |
| AfriCinemas or the cinema's internet is down | The device notices a **connection** failure (§9.2), switches to offline, checks scans against its copy, and uploads them later. |
| The server answers, but refuses access (signed out, no shift, access removed) | **Not offline.** Offline admissions stop or are limited (§6.4); staff sign in again or use the door list. |
| The scanner is closed, then opened with no connection | It starts from the device alone (§13) and keeps working within its offline grant. |
| The device is lost, broken or flat | Another device takes over if it's ready (§14.1); otherwise the door list. A manager revokes the lost device. |

## 4. How it works

```text
 /door/ (the installed scanner app)                   server
 ┌──────────────────────────────────────┐            ┌─────────────────────────────┐
 │ IndexedDB: grant · pack · admissions │──grant────►│ offline grant (§6)          │
 │            · journal (queue)         │◄─pack──────│ door pack + changes (§7)    │
 │ scan ─► online? redeem(scan_id) ─────┼───────────►│ redeem (scan_id, §9.1)      │
 │      └► offline: decide locally,     │            │                             │
 │         commit, then show (§9.4)     │──upload───►│ journal, reconcile (§11)    │
 └──────────────────────────────────────┘            └─────────────────────────────┘
```

The server stays the authority. Online, it decides, as now. Offline, the device decides, and the server records and reconciles those decisions later.

## 5. Decisions

**D1. An installable web app with our own service worker and manifest; Jac's `[client.pwa]` stays off.** Checked in Jac 0.38.3's source (JI-063): Jac's PWA worker is registered at `/static/sw.js`, so it controls only `/static/`. It precaches addresses the page doesn't load, keeps nothing fetched later, and, when it activates, **deletes every cache with another name**, which would include ours. So we don't turn it on. Instead the scanner is a small app of its own at **`/door/`**:
- **The manifest:** `/door/manifest.webmanifest`, with `id` and `start_url` `/door/` and `scope` `/door/`.
- **The service worker:** `/door/sw.js`, scope `/door/`.
- **The page:** the scanner page at `/door/<cinema>`.

All three are served by custom routes. It's installed to the home screen from the back office's scanner page, and it reuses the scanner's existing components.

**D2. Offline checks use the copy's list of tickets.** A reference is 16 random characters, 80 random bits (ADR-0020), and can't be guessed. Offline, the device reads the reference from `TKT1.<reference>.<signature>`, or a typed reference, and looks it up. **It does not check the QR's signature:** that needs the server's secret, which never leaves the server. A forged code with a made-up reference isn't in the copy. A copied real code is caught as used on the same device, or afterwards (D4).

**D3. The device keeps hashes of references.** See §7.2 for the exact rule. A stolen device then can't give up references in bulk. It doesn't make browser storage tamper-proof, and an unlocked stolen device can still be used to scan within its grant (§6).

**D4. Each device knows only its own admissions while offline** (O1, accepted). Two offline devices on one showtime can admit a copied ticket twice. The server finds it afterwards (§11.3). The scanner warns when another device was **last seen** on the same showtime (§14.2); during an outage it can't know whether that device is still there.

**D5. Every scan has an id, online and offline.** The device makes and stores a `scan_id` **before** sending any redemption (R3). The online endpoint and the upload share one record per id (§9.1, §11). That way a scan whose online answer was lost is recognized, not counted twice.

**D6. A scan journal, separate from ticket state.** What staff did at the door (scans, refusals, admissions, let-ins) is a journal of events. Redeeming a ticket is a separate result of reconciling them. Reports keep the two apart (§12).

## 6. The offline grant

### 6.1 What it is

The server issues a grant when the scanner syncs online, and records it. It's what lets a device make admissions offline:

| Field | Meaning |
|---|---|
| `grant_id` | Random id, recorded on the server |
| `tenant_id`, `member_id`, `device_id` | Whose and where |
| `venue_ids` | Venues where the member may scan (`tickets.scan`), at issue time |
| `issued_at`, `expires_at` | Valid until the **earlier** of the member's shift ending and the end of the last showtime in the pack + 1 hour, and never more than 14 hours |
| `policy` | `door-policy/1` (§17) |

### 6.2 Rules

- **R4:** The device MUST make no offline admission without an unexpired grant (by its corrected clock, §7.6), for a showtime at one of the grant's venues.
- **Renewal:** the grant is renewed on every successful sync. A device whose grant ends within 30 minutes says "Go online to keep scanning offline", for example near the end of a shift.
- **Expired offline:** the device refuses new admissions offline and says "Offline scanning has ended for this device: use the door list or go online." Pending uploads are kept (R2).

### 6.3 Revocation

A manager can revoke a device or a member's grants (Staff page). Revocation also happens when the member's role or membership is removed, or the cinema turns offline scanning off. **A revoked grant can't reach a disconnected device;** the device learns of it on its next contact and then deletes its pack. Admissions uploaded under a revoked grant:
- if their event time is **before** the revocation, they're processed normally;
- if it's **after**, they're kept as evidence for review (**Admitted after revocation**, §11.3). They never redeem a ticket automatically, and they're never discarded.

### 6.4 Connection failure vs refusal

- **R5:** The device MUST treat only these as a lost connection: a network error, a timeout, and HTTP 502, 503 or 504. An authorization answer MUST NOT switch it to offline.

| Server answer | Device does |
|---|---|
| Network error, timeout, 502/503/504 | Offline (§9.2) |
| 401: signed out or token expired, while the server is reachable | Asks for sign-in. It may continue under a valid grant for **15 minutes** while staff sign in, and says so |
| 403, `no_shift`, `forbidden`, grant revoked | Stops offline admissions at once, deletes the grant, and keeps pending uploads |
| A business refusal (already used, wrong showtime…) | Shows it; it's an answer, not an outage |

## 7. The door pack and its sync

### 7.1 Contents

One pack per device and grant: the showtimes at the grant's venues whose doors open within the next **6 hours** (O5), or are open now.

```json
{
  "pack_version": "door-pack/1",
  "pack_id": "uuid", "grant_id": "...", "tenant_id": "...",
  "server_time": "2026-11-01T16:01:10.123+00:00",
  "salt": "base64url of 32 random bytes, no padding",
  "cursor": "opaque",
  "cinema": {"name": "Anga Cinemas", "timezone": "Africa/Nairobi", "doors_open_minutes": 45},
  "showtimes": [{"screening_id": "...", "movie_title": "Rafiki", "starts_at": "...",
                 "ends_at": "...", "screen": "Screen 2", "venue_id": "...",
                 "venue": "Diamond Plaza", "state": "published", "version": 12}],
  "tickets": [{"tid": "ticket node id", "h": "hash (§7.2)", "screening_id": "...",
               "seat": "F7", "ticket_name": "Adult", "format": "3D", "glasses": true,
               "status": "issued", "used_at": "", "used_where": "Main door",
               "version": 3}]
}
```

**Notes:**
- **`tid`** is the ticket's opaque id. It isn't a credential: redemption needs the reference. Local admissions are keyed by `tid`, so they survive a pack being replaced with a new salt (R8).
- **`status`:** `issued`, `used`, `voided` or `refunded`. A showtime's `state` is its stored value: `published`, `sales_closed`, `cancelled` and so on.
- **`used_where`:** the **device's name** only, never a staff name or email (§16).
- **Not in it:** references, the booker's details, prices, M-Pesa codes.

### 7.2 Hashing

`h = lowercase hex SHA-256 of UTF-8("door1|" + salt + "|" + R)`, where:
- `R` is the reference upper-cased, with dashes and spaces removed: 16 characters from `23456789ABCDEFGHJKLMNPQRSTUVWXYZ`;
- `salt` is the pack's salt as base64url without padding.

A device MUST reject a reference that doesn't normalize to 16 such characters as `invalid_code` (R6).

**Test vector** (both implementations MUST match it):

```text
salt   = AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8   (bytes 0..31)
R      = 7K2M9QXR4HJNP3WD                              (from "7K2M-9QXR-4HJN-P3WD")
h      = 4e73291af7471910ef674eb1656b2a4d644badae5e333a879ddefdd028cfd08c
```

### 7.3 The sync protocol

**Snapshot.** `door_pack` returns the whole pack and a cursor. The cursor is signed by the server and bound to the tenant, pack, grant and venues. The device MUST reject a cursor answer for another pack (R7).

**Changes.** Every ticket and showtime has a `version` that rises on every change, and a `changed_at` server timestamp. `door_pack_changes(cursor)` returns what changed since the cursor's time **minus 5 minutes of overlap**, in pages of 1,000 with a continuation, plus a new cursor.
- **Overlap:** it catches transactions that committed late.
- **Applying:** the device applies a record only if its `version` is higher than what it holds. Applying twice changes nothing.
- **Removals:** an entry with `removed: true` means the ticket or showtime has left the pack (moved to another showtime, or showtime out of the window).
- **Changed settings:** cinema settings that change decisions (`doors_open_minutes`, the timezone) come with every change answer.

**Full resync** happens when the cursor is more than **30 minutes** old, when the server answers `resync`, when the grant's venues change, or every **2 hours**. The device builds the new pack beside the old one, then switches in one transaction.

**Applying is atomic.** R8: The device MUST apply a page of changes **and** advance its cursor in one IndexedDB transaction, and MUST keep its own pending admissions separate from server state. An incoming `issued` never makes a ticket the device admitted, but hasn't had acknowledged, usable again.

### 7.4 The salt

Each full pack has a new salt. The old pack's hashes are dropped when the new pack is switched in. Pending admissions stay, keyed by `tid`. The reference waiting in the journal is held as typed (§8.2), not hashed, so it doesn't depend on the salt.

### 7.5 Freshness on screen

"Tickets as of 19:02" is the server time of the last **applied** sync, never just the last successful health check (R1).

### 7.6 The clock

Each sync measures the round trip: `offset = server_time - (sent + received) / 2`, with uncertainty `round trip / 2`.
- **Offline,** the device uses its own clock plus the last offset, and records the uncertainty with every event.
- **Moved clock:** if the device's clock jumps (detected against `performance.now()` between events, or after a restart), it marks its time **unverified** until the next sync, and says so.
- **Wrong clock:** over 5 minutes off, the scanner says "This device's clock is wrong".
- **On the server,** every uploaded event keeps both the device's estimate (and its uncertainty) and the server's receipt time. An event whose order is uncertain is flagged, not trusted.

## 8. On the device

### 8.1 Stores (IndexedDB database `africinemas-door`, schema version 1)

| Store | Holds | Deleted when |
|---|---|---|
| `device` | `device_id`, the device's name | Never (until storage is cleared) |
| `grant` | The current grant | Expired, revoked, or the member signs out |
| `pack` | Showtimes, tickets (by `h` and `tid`), cursor, salt, settings | Replaced, expired, revoked, sign-out |
| `admissions` | Local admissions by `tid`: when, scan id | Acknowledged by the server **and** the showtime has ended |
| `journal` | Every event to upload (§8.2) | Durably acknowledged by the server (R2) |

### 8.2 The journal entry

Fields:
- `scan_id`: a UUID, made once;
- `seq`: the device's own order;
- the member, device and grant ids;
- the showtime;
- `reference`: as typed or read. It's a ticket credential, so it's kept only until acknowledged;
- the device's estimated time and its uncertainty;
- the pack's id and the data's age;
- the decision: admit, refuse with its code, or let in anyway (§10);
- `outcome`, from the server: empty until acknowledged.

### 8.3 Atomic decisions

R9: For each offline scan, the device MUST, **in one IndexedDB `readwrite` transaction** over `pack`, `admissions` and `journal`:
1. look the ticket up;
2. check `admissions` for it;
3. decide;
4. if admitting, write the admission;
5. write the journal entry.

It MUST show ✓ only after the transaction completes. If the transaction fails, it shows "Not saved: scan again".

Two tabs or windows on one device are covered: IndexedDB transactions on the same stores don't overlap. The scanner also keeps one active tab (a `BroadcastChannel` lock), and a second tab says "The scanner is open in another window".

### 8.4 Storage

On first use the scanner calls `navigator.storage.persist()` and `navigator.storage.estimate()`.
- **Not persisted:** readiness says so ("This browser may clear offline data: install the app").
- **Under 20 MB free:** readiness fails.

Browsers may still evict storage, and WebKit documents policies, not guarantees. So the readiness check (§14.1) re-verifies the store every time the scanner opens.

## 9. Scanning

### 9.1 Online

`redeem_ticket(tenant, screening_id, code, scan_id, device_id)`. The server records the scan in the journal under `scan_id`, bound to tenant, member, device, showtime and reference. R10:
- **A repeated `scan_id` with the same identity** MUST return the original result, without redeeming again.
- **A `scan_id` reused for a different identity** MUST be refused (`scan_id_conflict`).
- The redemption claim (`USED`) MUST carry the `scan_id`, so a retry after a crash between claiming and saving finds **its own** claim and completes the save (§11.2), instead of reporting "already used".

The device writes the journal entry **before** sending (R3). A response that arrives late is matched to its entry by `scan_id`, and MUST NOT overwrite a later scan's result on screen.

Old clients without `scan_id` keep working as today, until the version cut-off (§17).

### 9.2 Online or offline

- **Offline:** a request fails as in R5, or takes over **4 seconds**. The device switches at once.
- **Back online:** a background check succeeds (`/healthz`, then an authorized sync). The device uploads its journal (§11), applies changes, then says "Online".
- **A timed-out online scan** is decided offline under the same `scan_id` and uploaded. If the server did redeem it, reconciliation returns the original result: **one redemption, no double entry**.

### 9.3 Live but not able to admit

Inside the grant but with a 401 (§6.4), the device continues for 15 minutes with a banner. On 403, `no_shift` or revoked, it stops admitting.

### 9.4 Offline decisions

Checked in this order, matching the online code (`_reference` in `redeem_api.jac`):

| # | Check | Code | Shown |
|---|---|---|---|
| 1 | It's a snack pickup code (`SNK1.`) | `snack_code` | ✗ "This is a snack pickup code. It's collected at the snack counter." |
| 2 | Not a `TKT1.` code, nor a typed reference that normalizes (R6) | `invalid_code` | ✗ "This isn't a ticket code from this cinema." |
| 3 | No unexpired grant for this showtime's venue (R4) | `offline_not_allowed` | ✗ "Offline scanning has ended for this device" |
| 4 | The hash isn't in the pack | `not_on_list` | ✗ "Not on this device's list (tickets as of 19:02)", then **Let in anyway** (§10) |
| 5 | In the pack, for another showtime | `wrong_showtime` | ✗ "This ticket is for Rafiki at 21:00". Only for showtimes in the pack: a ticket for one outside the window reads as `not_on_list` |
| 6 | Showtime cancelled or unpublished | `showtime_closed` | ✗ |
| 7 | Before doors open or after the end, by corrected time | `too_early` / `showtime_over` | ✗ |
| 8 | `voided` / `refunded` in the pack | `ticket_voided` / `ticket_refunded` | ✗ |
| 9 | `used` in the pack | `already_redeemed` | ✗ "Already used at 19:12 at Main door" |
| 10 | Admitted on this device and not yet acknowledged | `already_redeemed` | ✗ "Already used at 19:14, on this device" |
| 11 | Otherwise | admit | ✓ seat, type, 3D, glasses |

Each answer is shown **in words** as well as colour, sound and vibration. Sound and vibration are extras, never the only signal (WCAG 2.2). Results are announced to screen readers (`role="status"`).

## 10. Let in anyway

For a person not on the device's list (check 4) who shows a ticket email or M-Pesa message. Anyone who can scan may do it (O2).

- **Recorded:** the M-Pesa code (required), the number of people let in on it (default 1), and the seat or seats.
- **One code can cover a group.** A booking's single M-Pesa payment can pay several seats. If the code was already recorded on this device, the scanner asks "This code already let 2 people in at 19:20. Is this person in the same booking?" before recording more. It doesn't refuse.
- **Only M-Pesa.** Cash bought on paper during the outage is part 4's paper sales, not this.
- **Same journal:** let-ins go into the journal as their own kind of event, and are reconciled centrally (§11.3).

## 11. Uploading and reconciling

### 11.1 Uploading

`upload_door_scans(tenant, device_id, protocol, entries)` sends batches of up to 100, oldest first. Each entry gets its own answer:
- **`recorded`**, or **`exception`** with a kind: final;
- **`retry`**: try again later;
- **`rejected`** with a reason: final, kept for review, for example a revoked grant (§6.3).

**R2:** The device MUST delete a journal entry, and its reference, only after a **final** answer for that entry. A batch with both final and `retry` answers deletes only the final ones. A lost response means everything is sent again, which is safe under R10.

### 11.2 On the server

Each entry is processed in steps that recover if the server dies part-way. R11:
1. **Claim** `door-scan:<scan_id>` with a fingerprint of the entry's identity. Seeing its own claim again means "processing or done"; a different fingerprint means `scan_id_conflict`.
2. **Write** the journal record (`DoorScan`) in the graph transaction, with the state `received`.
3. **For an admission,** redeem through the `USED` claim, carrying the `scan_id`:
   - if the claim is ours, from an earlier attempt, complete the ticket's save;
   - if it's someone else's, it's a conflict (§11.3).
4. **Set the record's outcome** and state `done` in the same transaction as the ticket's save.
5. **Answer** with the outcome only after step 4 has committed.

A claim (step 1) with no record (step 2) means an attempt died before writing. The next attempt simply continues. Claims commit outside the graph transaction (`core/claims.jac`), which is why each step must be safe to repeat.

### 11.3 Outcomes

| Found | Recorded as |
|---|---|
| An admission matching a ticket that is valid at the event time | **Redeemed** (offline). Attendance counts it once |
| The ticket was already redeemed by another scan (online, or another device) | **Double entry**: both events, devices and times. Attendance still counts the ticket once |
| The ticket was refunded or voided before the event time | **Admitted after refund**. Money untouched; managers decide |
| An admission under a revoked grant, after revocation | **Admitted after revocation**: kept, not redeemed |
| Let in anyway: the code matches a successful payment at this cinema, for this showtime | Allocated against that booking's **seats**. Up to the booking's seat count, its tickets are **redeemed**; beyond it, **Over-admitted** |
| Let in anyway: the payment completed the booking late (still pending when it succeeded, so tickets were issued) | As above |
| Let in anyway: the payment went to a **refund task** (an order already released, or a snack add-on after the start) | **Let in, refund pending**: the manager chooses to keep the payment as admission (closing the refund task with a note) or to refund |
| Let in anyway: no matching payment **48 hours after the upload was received** | **Unmatched let-in** |
| Refused at the door | Kept in the journal; never an admission |

Matching uses the verified payment record: same cinema, the M-Pesa receipt (claimed once, `RECEIPTS`), the order's showtime, its amount, and its refund state. A device's word is never enough.

### 11.4 Where managers see them

- **Back office:** a **Door exceptions** list for owners, general managers and box office managers. Each exception has its showtime, the events, the devices, the times (estimated and received) and the outcome. It stays open until someone marks it handled, with a note (audited).
- **Overview:** "3 door exceptions to look at".
- **Email:** the venue's general managers get one email per showtime that ended with exceptions.

## 12. The journal, tickets, attendance and audit

- **The journal (`DoorScan`)** is append-only. Each record has:
  - the client's decision, and the server's outcome;
  - the estimated event time with its uncertainty, and the receipt time;
  - the pack id and its data age;
  - the member, the device and the grant.
- **Tickets** change only through reconciliation (§11.2), and keep `used_at` (the event time), `used_by`, and new `used_offline` and `used_scan_id` fields.
- **Attendance** keeps counting tickets that are `used`, once each. Reports add, per showtime:
  - admissions let in anyway (matched or unmatched);
  - double entries;
  - admissions after refund.
  Refused attempts are never admissions. Financial figures are untouched.
- **The audit log:**
  - one `ticket.scanned` per ticket redeemed, detail `offline`;
  - `door_scan.exception` per exception;
  - `door_grant.issued` (the first each day per device) and `door_grant.revoked`;
  - `door_exception.handled`.

## 13. Starting up with no connection

R12: The installed scanner MUST start and scan with no connection, after one successful online visit, without calling `my_access` or any other endpoint. It MUST use the grant and pack in IndexedDB.

- **The page, outside the back office:** `/door/<cinema>` is a page of its own, outside the back office's `AuthGuard` and without `BackOffice.load`. It reads the grant and pack first, then tries the network. With no grant, it says "Open the scanner online once to get it ready".
- **What the service worker keeps** (`/door/sw.js`, cache `door-shell-<bundle hash>`):
  - the `/door/` page shell, **network first**;
  - the client bundle, styles, fonts and the QR worker, **cache first**, kept by the exact addresses the page loads (the bundle's hash is in its address and in the cache's name).
  It never caches `/function/` or `/walker/` answers.
- **Updates:** a new worker installs beside the old one and is **activated only when the journal is empty**, or at the next cold start. The old shell's cache is deleted only after the new one is complete.
- **Database changes:** IndexedDB migrations run forward-only in the upgrade transaction. A failed migration leaves the old version in place, and the scanner says "Update failed: keep scanning, and tell your manager".
- **Signed out:** an expired token doesn't end offline scanning within the grant (§6). Uploads wait for the same member's sign-in.

## 14. Screens

### 14.1 Ready for offline

Shown on opening, and on the back office's Overview for the device in use. **Ready** needs all of:
1. the page is controlled by the scanner's service worker, with the shell cached;
2. a complete pack, applied within the last 5 minutes;
3. an unexpired grant;
4. a successful test write and read in IndexedDB;
5. persistent storage (or a warning that it isn't).

Shown as "Ready for offline: 3 showtimes, 1,104 tickets, as of 18:58", or "Not ready: <what's missing>".

### 14.2 Banners

| State | Banner |
|---|---|
| Online | "Online · tickets as of 19:02" |
| Offline | "Offline: checking against tickets as of 19:02. Scans upload when we're back." |
| Offline over 30 minutes | Adds: "Check people not on the list against their M-Pesa message." |
| Signed out, still reachable | "Sign in again within 15 minutes to keep scanning" |
| Grant ending soon / ended | §6.2 wording |
| Uploading | "Back online: uploading 37 scans…" |
| Uploaded with exceptions | "Uploaded. 2 door exceptions for your manager." |
| Clock wrong or unverified | §7.6 wording |
| Another device seen | "Main door was checking this showtime at 19:01. While offline, use one device per showtime." |

### 14.3 The device's name

The device is named on first use ("Main door"). The name appears in `used_where` and Door exceptions. Clearing the browser's storage makes it a new device.

### 14.4 Signing out

With entries still in the journal, signing out asks first. If the member signs out anyway, the journal is kept, and only the **same member's** next sign-in uploads it. Pack and grant are deleted.

## 15. Server changes

| Endpoint (`def:protect`, tenant scope) | Does |
|---|---|
| `door_grant(tenant, device_id, device_name)` | Issues or renews the grant (§6). Refused without a shift and `tickets.scan`, or with offline scanning off |
| `door_pack(tenant, device_id, grant_id)` | The snapshot (§7.1) |
| `door_pack_changes(tenant, device_id, cursor)` | Changes (§7.3), or `resync` |
| `redeem_ticket(…, scan_id, device_id)` | Today's endpoint, with the two new arguments (§9.1) |
| `upload_door_scans(tenant, device_id, protocol, entries)` | §11 |
| `door_exceptions(tenant, venue_id, open_only)` / `handle_door_exception(tenant, id, note, action)` | §11.4 |
| `revoke_door_device(tenant, device_id)` | §6.3 |

**New records:**
- `DoorGrant`, `DoorDevice`, `DoorScan` (the journal) and `DoorException`;
- `version` and `changed_at` on `Ticket` and `Screening`;
- `used_offline` and `used_scan_id` on `Ticket`;
- the per-cinema setting **Offline scanning**: off by default, on for the pilot cinemas.

**Also:**
- each endpoint in the isolation registry, with audit actions and labels;
- a scheduled job for the 48-hour unmatched let-ins, which checks in (16.2).

## 16. Data inventory

| Data | Where | Purpose | Kept | Who reads it | Deleted |
|---|---|---|---|---|---|
| Hashed references, seats, ticket types, showtimes | Device (`pack`) | Offline checks | Until replaced or expired, ≤ grant | The device | Replaced, expired, revoked, sign-out |
| References waiting to upload | Device (`journal`) | Uploading admissions | Until acknowledged | The device | On a final answer (R2) |
| Device name, device id | Device and server | Showing where a ticket was used; revoking | Server: while the cinema is active | Cinema staff with `tickets.scan`; managers | Device: storage cleared. Server: with the cinema |
| Grant | Device and server | Authorizing offline admissions | Server: 90 days | Managers (who scanned offline) | 90 days |
| Journal: events, member, device, times, M-Pesa codes of let-ins | Server | Reconciling; exceptions; audit | 1 year (as audit records) | Owners, general and box office managers | After 1 year |
| Door exceptions | Server | Managers' follow-up | 1 year | As above | After 1 year |

**What changes elsewhere:**
- **This is new personal data:** staff activity and devices, and the M-Pesa codes of people let in anyway. The privacy policy's staff section and the cookie notice's device storage (`africinemas-door`, for staff only) are updated in the same PR as the endpoints. The test that every browser storage key is listed covers the new database.
- **Staff names on the device:** the pack names devices, never staff. Today's `staff_name()` can return an email; it's not used in the pack.
- **Salted hashes** protect against bulk disclosure of references. They don't stop an unlocked stolen device from scanning within its grant; revoking it does (§6.3).

## 17. Versions and compatibility

| Thing | Version | Unknown version |
|---|---|---|
| Pack | `door-pack/1` | The device refuses the pack and says "Update the scanner" (the service worker's update path) |
| Upload protocol | `door-upload/1` | The server answers `retry` with `update_required`. Nothing is lost |
| IndexedDB schema | `1` | §13 migrations |
| Decision policy | `door-policy/1` | Carried in the grant |

- **Old clients:** the server accepts the current and the previous protocol versions.
- **All timestamps:** ISO 8601 with offset, milliseconds.
- **Limits:** references are 16 characters; device names up to 40 characters; a batch up to 100 entries.

## 18. Devices

- **Android 10 or later** with current Chrome (current Chrome needs Android 10+), installed to the home screen. Recommended.
- **iPhone, iOS 16.4 or later,** installed to the home screen (O4).
- **Camera** for QR codes; typing a reference works without one.
- **20 MB free** (§8.4).
- **Before doors open each day,** open the scanner online once and see **Ready for offline**.

## 19. Building it

| # | Part | Size |
|---|---|---|
| S1 | **Trial:** the `/door/` routes, manifest and service worker (D1, §13). On Android Chrome and an iPhone, installed: **force-close → airplane mode → launch from the home screen → scan a test ticket from IndexedDB**, also with an expired sign-in token. Also: storage persistence, the camera when installed, and a deploy replacing the shell while an entry is in the journal. Custom routes serving JavaScript with the right content type are part of the trial. | S (1–2 days) |
| 1 | Server: grants, pack, change sync with versions (§6, §7) | M |
| 2 | Server: `scan_id` on online redemption, the journal, recoverable steps, uploads (§9.1, §11.2) | M |
| 3 | Device: stores, atomic decisions, sync loop, connection rules, clock (§7, §8, §9) | L |
| 4 | Device: screens, readiness, banners, signing out (§14) | M |
| 5 | Reconciliation outcomes, Door exceptions, let in anyway and matching (§10, §11.3, §11.4) | M |
| 6 | Data inventory changes: privacy policy, cookie notice, retention jobs (§16) | S |
| 7 | Tests (§20), runbook, training notes | M |

Each part is a PR behind the per-cinema **Offline scanning** setting, so it can be switched off without a deploy. A switch-off can't reach devices already offline; their grants expire on their own (§6.1).

## 20. Testing

**Unit:**
- hashing against the test vector, in the server and the device code;
- normalizing references (R6);
- each row of §9.4;
- the clock offset and its uncertainty;
- connection-failure classification (R5).

**Integration (server):**
- the pack's contents and its lack of personal data;
- changes after a sale, refund, scan elsewhere, cancellation, and a `doors_open_minutes` change;
- removals, pagination, `resync`, and a cursor for another pack (R7);
- R10 and R11, including a crash injected after each step (the existing fault points, `AFRICINEMAS_FAULTS`);
- every outcome in §11.3;
- grants: shift ended, role removed, member disabled, device revoked, offline scanning off;
- the isolation registry and audit actions.

**End to end** (Playwright, `context.set_offline(True)`; a service worker in a real Chromium):
- scan online; lose the response; reconcile: **one redemption, no double entry**;
- offline: admit, already used, not on the list, let in anyway (two people on one code);
- two tabs scanning the same ticket at once: one admission;
- a stale change arriving after a local admission: the ticket stays used;
- a pack replaced while admissions are pending;
- cold launch with no connection and an expired token (R12);
- 401, 403 and `no_shift` don't switch to offline (R5);
- an upload whose answer is lost; a batch with final and retryable answers (R2);
- a deploy while the journal has entries;
- full storage, or storage cleared;
- a late payment with a refund task, matched to a let-in;
- two offline contexts admitting the same ticket: one double entry;
- reading IndexedDB to confirm no references beyond the journal's, and no customer details.

**Rehearsal on real phones** (an Android phone and an iPhone, 200 printed tickets, 3 hours). Pass if:

| Measure | Target |
|---|---|
| Offline scan to answer, 95th percentile | ≤ 300 ms |
| Age of applied sync while active and online, 95th percentile | ≤ 60 s |
| Cold launch offline from the home screen | 10 out of 10 |
| Uploading 500 queued scans after reconnecting | ≤ 30 s |
| Battery over 3 hours of scanning | ≤ 20% |
| Admissions lost | 0 |

**Load:** a pack of 2,000 tickets is built on the server within 1 s and opened on a low-end Android phone within 2 s.

## 21. Done when

1. **Every rule R1–R12 has a passing test** (§20).
2. **With the server stopped,** an installed scanner, cold-launched offline, admits valid tickets in its pack, and refuses used, wrong-showtime and invalid ones with the online wording.
3. **After reconnecting,** each admission is redeemed once, a lost online answer causes no double entry, and each §11.3 case shows correctly in Door exceptions and reports.
4. **The rehearsal targets are met,** and the runbook "Scanning when we're offline" is followed by someone who didn't write it.
5. **`docs/failure-modes.md` rows 1.7, 1.9 and 1.10 are ✅.**

## 22. Decisions

| # | Question | Decided (owner, 2026-10-31) |
|---|---|---|
| O1 | Two offline devices on one showtime can admit a copied ticket twice, found afterwards | Accepted for the pilot, with the "last seen" warning |
| O2 | Who may let someone in anyway? | Anyone who can scan; every one reconciled and shown |
| O3 | Snack pickup codes offline now? | After the pilot |
| O4 | iPhones in the pilot? | Both, installed; Android recommended |
| O5 | How far ahead a device keeps showtimes | Doors opening within 6 hours |

Defaults in this version, which the owner can change before part 1:
- the grant lasts to the shift's end and at most 14 hours (§6.1);
- 15 minutes of scanning after a sign-in expires while reachable (§6.4);
- let-ins are matched within 48 hours of upload (§11.3);
- journal and exceptions are kept 1 year (§16).
