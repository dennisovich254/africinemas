# Specification: the offline scanner (plan 17.2b)

Status: **agreed** (owner, 2026-10-31: decisions O1–O5 as suggested). Needed **before the pilot** (owner, 2026-10-31). Closes failure modes 1.7, 1.9 and 1.10 (`docs/failure-modes.md`).

## 1. Why

Today every scan asks the server whether the ticket is real, for this showtime, and unused (`core/booking/redeem_api.jac`). If AfriCinemas is down, or the cinema's own internet is, the scanner says nothing useful. Staff then either let everyone in or no one, and copied tickets get in.

The door list (17.2) is the fallback on paper. But a list is out of date from the moment it's made, and many tickets are bought on the day itself. At a full premiere, ticking 400 names by hand is slow and error-prone.

The offline scanner keeps checking tickets when it can't reach us, against a copy of the showtime's tickets kept on the device and updated every few seconds while it can.

## 2. Goals and non-goals

**Goals**
1. Door staff keep scanning QR codes and typed references during an outage, with the same answers as online: let in, already used (when, and on which device), wrong showtime, too early, showtime over, not a valid ticket.
2. The copy on the device is never more than **one minute** old while the device is online, so an outage loses at most the last minute's bookings.
3. Nothing scanned offline is lost: every offline scan reaches the server when the device is back online, and the server's records end up as if the scans happened online.
4. Problems an offline door can't prevent are **found and shown afterwards**: the same ticket let in on two devices, a ticket refunded in the meantime, people let in who weren't on the list.
5. Nothing on the device reveals customers' details, or lets someone who steals the device make tickets.
6. Works on the phones cinemas have: Android phones with Chrome first.

**Not in scope** (later, if needed)
- Selling at the box office offline (failure modes 1.11; paper sales are 17.2, part 4).
- Devices talking to each other over the cinema's local network.
- A native app from an app store (18.1).
- Changing how tickets are signed: not needed (decision D2).

## 3. When it's used

| Situation | What happens |
|---|---|
| Everything works | Scans go to the server as today. In the background, the device keeps its copy of the tickets up to date. |
| AfriCinemas is down | The device notices within seconds, says "Offline", and checks scans against its copy. The scans upload when we're back. |
| The cinema's internet is down, or the door has no signal | The same as above. |
| The connection comes and goes | The device switches between online and offline on its own. A scan is never lost or counted twice. |
| The device is off, broken or out of battery | Another device takes over: sign in, open the scanner, and it downloads the copy (if online). If none can, the door list (17.2). |
| Doors open while we're already down | Works only if the device downloaded the showtime before the outage. Staff open the scanner when they arrive, before doors open (§9.1, "Ready for offline"). |

## 4. How it works

```text
          online                                        offline
┌──────────────────────────────┐            ┌──────────────────────────────────┐
│ scan ─► server redeems ─► ✓  │            │ scan ─► the copy on the device   │
│   (and the device's copy     │            │        ─► ✓ / ✗, recorded on     │
│    marks it used)            │            │           the device, queued     │
│                              │            │                                  │
│ every ~30 s: the device asks │  ─────────►│ every ~15 s: try to reach the    │
│ for changes since its last   │  ◄─────────│ server; when it answers, upload  │
│ copy (new tickets, refunds,  │            │ the queue, then fetch changes    │
│ scans on other devices)      │            │                                  │
└──────────────────────────────┘            └──────────────────────────────────┘
```

The server stays the authority. When the device is online, the server decides, exactly as now. The device decides only while it is offline, and the server records its decisions afterwards.

## 5. Decisions

**D1. An installable web app (PWA) with our own service worker, not a native app.** The scanner page is installed to the phone's home screen, a service worker keeps the scanner's code on the device so it opens with no connection, and the tickets are kept in the browser's IndexedDB.
- Cinemas need nothing from an app store, and the scanner stays the same code as today's `ScannerSection.jac`.
- **Jac's own PWA support isn't enough** (checked in Jac 0.38.3's source, 2026-10-31; JI-063). A `[client.pwa]` table gives the manifest, icons and install banner, so the app installs, but its service worker can't open the app offline:
  1. it's registered at `/static/sw.js`, so it controls only pages under `/static/`, never `/app/...`;
  2. it precaches `/static/client.<hash>.js`, while the page loads `/static/client.js?hash=…`, and it skips `dist/assets/` (the QR scanner's worker);
  3. it keeps nothing fetched later (only `/api/`, which Jac's endpoints don't use);
  4. it can keep serving an old app after a deploy.
- **So:** we keep Jac's manifest and icons (or write our own manifest), and serve **our own service worker** from a custom route at the site's root (`/scanner-sw.js`, scope `/app/`). It:
  - keeps the scanner page's HTML, network first;
  - keeps the client bundle, styles, fonts and the QR worker, cache first, keyed by the bundle's hash, which is also in the cache's name, so a deploy replaces them;
  - never caches `/function/` or `/walker/` answers: the tickets live in IndexedDB.
- *iOS:* Safari may delete a website's storage after seven days without a visit unless the app is installed to the home screen. Installed, it keeps it. Both Android and iPhones are supported in the pilot (O4), installed; Android is recommended.

**D2. Offline checks use the copy's list of tickets; no change to ticket signing.** A ticket's reference is 16 random characters, 80 random bits (ADR-0020), so nobody can guess one. A code is valid offline if its reference is in the device's copy for this venue's showtimes.
- QR codes are signed with the server's secret key (HMAC-SHA256, `TKT1`), which must never be on a device, so the device doesn't check the signature. It doesn't need to: a forged QR with a made-up reference isn't in the copy, and a copied real QR is caught as already used (on the same device) or afterwards (on another, D4).
- The device reads the reference out of `TKT1.<reference>.<signature>` (or a typed reference) and looks it up.

**D3. The device keeps hashes of references, not the references.** If the device held the references, someone with a stolen phone could type them in at a door, or print them. So the copy holds `SHA-256("door1|" + pack_salt + "|" + reference)` for each ticket, with a random `pack_salt` per copy. The device hashes the scanned reference the same way and looks that up.
- A stolen device then reveals only seats and ticket types, and hashes that can't be turned back into references (80 random bits).

**D4. Each device keeps its own list of what it let in; two devices offline at once can let the same ticket in twice.** Devices don't talk to each other (not in scope), so when two doors of one screen are both offline, a copied ticket could get in at each. Afterwards the server finds it (§8.3), records a **double entry**, and shows it to the cinema's managers.
- To keep it rare, the scanner tells staff "Use one device per showtime while offline" when a second device is checking the same showtime.
- Accepted for the pilot (O1).

**D5. Offline scans count as the staff member's.** A scan offline is recorded as the signed-in member's, with the device's id, when it was scanned (the device's clock, corrected by its measured offset from the server's, §6.4), and "offline". The audit log records it as `ticket.scanned` with detail `offline` when it uploads.

**D6. Online stays exactly as today.** An online scan calls `redeem_ticket` as now. The copy is only a fallback and never changes an online answer.

## 6. The copy of the tickets ("door pack")

### 6.1 What's in it

One pack per device, covering the showtimes it may check: every showtime at the member's venues **with tickets.scan** whose door opens within the next **6 hours**, or is open now. That's from `doors_open_minutes` (45 unless changed) before the start until the end, as `door_is_open` decides today.

```json
{
  "pack_id": "uuid",
  "made_at": "2026-11-01T16:01:10+00:00",
  "cursor": "opaque, for asking what changed since",
  "pack_salt": "32 random bytes, base64",
  "expires_at": "the last showtime's end + 2 hours",
  "member_id": "...", "device_id": "...",
  "cinema": {"name": "Anga Cinemas", "timezone": "Africa/Nairobi", "doors_open_minutes": 45},
  "showtimes": [
    {"screening_id": "...", "movie_title": "Rafiki", "starts_at": "...", "ends_at": "...",
     "screen": "Screen 2", "venue": "Diamond Plaza", "state": "on_sale"}
  ],
  "tickets": [
    {"h": "hash of the reference (D3)", "screening_id": "...", "seat": "F7",
     "ticket_name": "Adult", "format": "3D", "glasses": true,
     "status": "issued | used | voided | refunded",
     "used_at": "", "used_where": "Scanner 2 · Mary"}
  ]
}
```

**Not in it:** references, the booker's name, email or phone, prices, or M-Pesa codes.

**Size:** about 150 bytes a ticket, so a full 500-seat screen is about 75 KB, and a day at a busy multiplex a few hundred KB.

### 6.2 Getting it, and keeping it up to date

- **First download:** when the scanner opens (online), and whenever the set of showtimes in the window changes.
- **Changes:** every **30 seconds** while online, the device asks for changes since its cursor (`door_pack_changes`):
  - new tickets;
  - tickets voided, refunded or moved to another showtime;
  - tickets scanned on other devices;
  - showtimes cancelled or moved.
  The answer is small; usually empty.
- **Freshness:** the device records when it last heard from the server. The screen always says how old the copy is ("Tickets as of 19:02").
- **Expiry:** a pack is deleted when it expires, when the member signs out, or after 24 hours unused. It's never used for a showtime that has ended.

### 6.3 Where it's kept

- **IndexedDB on the device,** in its own database: tickets indexed by hash; showtimes; the queue of scans to upload (§8); and a log of decisions shown (for the device's own "already used here" answers).
- **If the browser refuses storage** (private mode, or the device is full), the scanner says "This device can't keep tickets for offline use" and still works online.

### 6.4 The device's clock

The door window and "already used at" depend on the time. The server sends its time with every pack and change, and the device keeps the difference (`offset = server_time - device_time`). Offline, it uses its own clock plus that offset. If the offset is over 5 minutes, the scanner warns: "This device's clock is wrong; fix it in Settings".

## 7. Scanning

### 7.1 Online or offline?

- **Online:** the last request to the server answered within **4 seconds**.
- **Offline:** a request failed, or took longer than 4 seconds. The device switches at once and says so.
- **Back online:** a background check (`/healthz`, then the change request) succeeds. The device uploads its queue (§8) before it says "Online" again.
- A scan that started online and got no answer within 4 seconds is decided offline. Its upload carries the same scan id, so if the server did receive it, it isn't counted twice (§8.2).

### 7.2 What the device answers, offline

Checked in this order, with today's online wording wherever it exists (`redeem_api.jac`):

| # | Check | Answer | Shown as |
|---|---|---|---|
| 1 | The code isn't a ticket QR (`TKT1.`) or a typed reference | `invalid_code` | ✗ "Not an AfriCinemas ticket" |
| 2 | It's a snack pickup code (`SNK1.`) | `snack_code` | ✗ "This is a snack pickup code…" (as online) |
| 3 | The hash isn't in the pack | `not_on_list` (new) | ✗ "Not on this device's list (tickets as of 19:02)". Then a **Let in anyway** option (§7.4) |
| 4 | It's for another showtime in the pack | `wrong_showtime` | ✗ "This ticket is for Rafiki at 21:00" |
| 5 | The showtime is cancelled or unpublished | `showtime_closed` | ✗ |
| 6 | Too early, or after the end (corrected clock, §6.4) | `too_early` / `showtime_over` | ✗ |
| 7 | Voided or refunded | `ticket_voided` / `ticket_refunded` | ✗ |
| 8 | Used: scanned online before the copy was made, or on another device | `already_redeemed` | ✗ "Already used at 19:12 on Scanner 2 · Mary" |
| 9 | Already let in on this device, offline | `already_redeemed` | ✗ "Already used at 19:14, on this device" |
| 10 | Otherwise | let in | ✓ seat, type, 3D and glasses, as online; recorded and queued |

### 7.3 Showing it

- **The result screen:** the same big ✓ or ✗ as today, plus a banner while offline: "Offline: checking against tickets as of 19:02. Scans upload when we're back."
- **Sound and vibration:** a distinct tone and buzz for ✓ and for ✗, so staff needn't read the screen in the queue.
- **The counter:** "212 in · 340 sold" for the chosen showtime, counting online and offline scans on this device, and others' scans known to the pack.

### 7.4 "Let in anyway"

For someone not on the list (check 3) who shows a ticket email or M-Pesa message, the same rule as the door list (failure modes 1.3):
- the staff member checks the message is to this cinema, for the right amount, and sent before the showtime;
- they record the M-Pesa code (required) and the seat, and the person is let in;
- it's queued as an **exception**, not as a ticket scan;
- the device refuses an M-Pesa code it has already recorded: "This M-Pesa code was already used at 19:20".

Anyone who can scan may let someone in anyway (O2); every one is listed as a Door exception.

### 7.5 Snack pickup codes

The snack counter (`concessions.collect`) can use the same mechanism for `SNK1` codes. It's the same pack design with the snack lines, and the same queue. **After the pilot** (O3): a missed snack hand-over is fixed afterwards, with no money lost.

## 8. Uploading offline scans

### 8.1 The queue

Every offline decision is written to the device's queue **before** the answer is shown, so a crash or flat battery loses nothing. Each entry:
- **its id:** a UUID, made once;
- **the code:** the reference, held on the device only until it uploads, then deleted;
- **the showtime;**
- **when it was scanned:** the corrected time;
- **the member and the device;**
- **the decision:** let in, refused with its code, or let in anyway with the M-Pesa code and seat.

### 8.2 Sending it

When back online, the device sends the queue in batches of 100 to `upload_door_scans`, oldest first, until it's empty. The server:
1. checks the member could scan at that venue then (`tickets.scan`), and that the scan time is believable: inside the showtime's door window, and not in the future;
2. treats each entry by its id: an id already received is answered with its first result, so a retried upload changes nothing;
3. for **let in**, redeems the ticket through the same claim (`USED`) as online, with `used_at` set to the scan time, `used_by` the member, and `offline: true`;
4. records the outcome per entry: `recorded`, or an **exception** (§8.3);
5. writes the audit log: one `ticket.scanned` per ticket, detail `offline`.

The device deletes an entry, and its reference, only when the server has answered for it. A failed batch is retried with backoff.

### 8.3 What the server can find afterwards

| Found | Means | Recorded as |
|---|---|---|
| The ticket was already used on another device | Two doors let the same ticket in (D4) | **Double entry**: both scans, devices, members and times |
| The ticket was refunded or voided before the scan | The pack was stale | **Let in after refund** |
| The ticket was used online before the offline scan | The pack was stale, or a copy of the QR | **Double entry** |
| Let in anyway: the M-Pesa code matches a payment for this showtime | Paid during the outage, now confirmed | **Matched** to its booking; the ticket is marked used. Settled, not an exception |
| Let in anyway: no payment matches within 48 hours | Possibly a fake message | **Unmatched entry** |

### 8.4 Where they show

- **Back office,** in a new **Door exceptions** list, for owners, general managers and box office managers: each with its showtime, seat, who scanned it and the outcome. The list is open until someone marks each one "Seen", with an optional note.
- **Overview:** "3 door exceptions to look at".
- **Email:** the venue's general managers get one email per showtime that ended with exceptions.
- **Reports:** attendance counts offline scans; a double entry counts once.

## 9. The scanner's screens

### 9.1 Ready for offline

On opening the scanner, before doors open, a status line:
- **ready:** "Ready for offline: 3 showtimes, 1,104 tickets, as of 18:58";
- **not ready:** "Not ready for offline: open the scanner while online", with the reason (no storage, never downloaded, signed out).

The overview (staff home) shows the same status for the device in use.

### 9.2 Banners

| State | Banner |
|---|---|
| Online, ready | "Online · tickets as of 19:02" (small) |
| Offline | "Offline: checking against tickets as of 19:02. Scans upload when we're back." (amber) |
| Offline, copy older than 30 minutes | Adds: "Check people not on the list against their M-Pesa message." |
| Uploading | "Back online: uploading 37 scans…" |
| Uploaded with exceptions | "Uploaded. 2 door exceptions for your manager." |
| Clock off | "This device's clock is wrong by 12 minutes. Fix it in Settings." |
| Second device on this showtime | "Another device is checking this showtime. While offline, use one device per showtime." |

All banners are announced to screen readers (`role="status"`), and every state is shown in words as well as colour.

### 9.3 The device's name

The first time a device opens the scanner, it makes a random `device_id`, keeps it in its own storage, and asks for a short name ("Main door", "Scanner 2"). The name is sent with the pack request and every upload, and used in "already used at 19:12 on Main door · Mary" and in Door exceptions. Clearing the browser's storage makes it a new device.

### 9.4 Signing in and out

- **Sign-in tokens last one day.** If the token expires while offline, the scanner keeps working on its pack until the pack expires, and asks for a sign-in only when it's back online, to upload. The queue stays on the device until then.
- **Signing out** with scans still queued asks first: "37 scans haven't uploaded yet. Stay signed in until they do?" Signing out anyway keeps the queue, which the next sign-in by the **same member** uploads. A different member can't upload another's queue.

## 10. Server changes

| Endpoint (all `def:protect`, tenant scope) | Does |
|---|---|
| `door_pack(tenant, device_id)` | The pack (§6.1) for the caller's scan venues. Audited as `door_pack.downloaded` the first time per device per day. |
| `door_pack_changes(tenant, device_id, cursor)` | What changed since `cursor`, and a new cursor. |
| `upload_door_scans(tenant, device_id, scans)` | Records offline scans and let-ins (§8.2); answers each one. |
| `door_exceptions(tenant, venue_id, open_only)` | The Door exceptions list. |
| `mark_door_exception_seen(tenant, exception_id, note)` | Audited. |

**New on the server:**
- **The change cursor:** a per-cinema sequence number, stamped on each ticket and showtime when it changes. The ticket's `status`, `used_at` and `used_by`, and the showtime's state and times, are what the pack needs.
- **A `DoorScan` record per uploaded entry,** kept 90 days. Ids are claimed (`door-scan` namespace), so an id is processed once whichever server copy gets it.
- **A `DoorException` record,** kept with the showtime's records.
- **`Ticket.used_offline`** and `used_device`.
- **The isolation registry, audit actions and labels** for each new endpoint (`tests/isolation/registry.jac`, `report_view.jac`).
- **A scheduled job** that turns "let in anyway" entries with no matching payment after 48 hours into **Unmatched entry** exceptions. It checks in as a job (16.2).

## 11. Security and privacy

- **On the device:** hashed references, seats, ticket types and showtimes only (D3). No names, emails, phone numbers, M-Pesa codes of bookings, or prices. Scanned references wait in the queue only until they upload.
- **A stolen device:** gives seats and hashes for at most the rest of the day. It can't make tickets: references can't be recovered from hashes. Signing the member out from the Staff page ends its uploads.
- **Malicious staff:** a member could mark tickets "used" offline that were never scanned. Uploads are attributed to them and audited, and the server rejects scan times outside the door window or in the future.
- **Replayed or altered uploads:** an upload needs the member's sign-in and their scan permission at that venue. An id is processed once, and a scan for a ticket of another cinema answers "unknown", as online.
- **Data protection:** no new personal data. The privacy policy's "what we keep on your device" (cookie notice, 15.0) gets the scanner's storage: "for staff only: today's tickets, without customer details". `tests/unit` gets the storage key in its every-key-is-listed check.
- **Permissions:** the same as scanning today (`tickets.scan` at the venue). Anyone who can scan may let someone in anyway (O2).

## 12. Requirements on devices

- **Android 9 or later** with a current Chrome, or an **iPhone with iOS 16.4 or later**, installed to the home screen (D1).
- **A camera** for QR codes. Typing a reference works without one.
- **50 MB of free storage;** a few MB are used.
- **The scanner installed to the home screen,** and opened online once before doors open each day.
- Cinemas are told this in the pilot's training (17.8).

## 13. Building it

| # | Part | Size |
|---|---|---|
| S1 | **Trial, with our own service worker** (D1; Jac's can't open the app offline, JI-063): a custom route serving `/scanner-sw.js` at the site's root, the manifest, and the scanner page reopened in airplane mode after one online visit, on Android Chrome and an iPhone, installed. Also: IndexedDB, the camera when installed, and a deploy replacing the cached app. One to two days. | S |
| 1 | Server: the pack, changes and cursor (§6, §10) | M |
| 2 | Device: storage, sync loop, online/offline switching, clock offset | M |
| 3 | Device: offline decisions (§7.2), queue (§8.1), sounds, banners, Ready for offline | M |
| 4 | Server: upload, ids processed once, exceptions (§8.2, §8.3) | M |
| 5 | Back office: Door exceptions, overview line, email | S |
| 6 | Let in anyway, and matching M-Pesa codes (§7.4, §8.3) | S |
| 7 | Tests (§14), runbook, training notes | M |

**Order:** S1, then 1 to 4 (the core), then 5 and 6. Each part is a separate PR, behind a per-cinema setting **Offline scanning** (on for the pilot cinemas), so a problem can be switched off without a deploy.

## 14. Testing

- **Unit:** the hashing (the device's and the server's agree, so the same reference gives the same hash); the decision table §7.2, case by case; the clock offset; reading `TKT1` and typed references.
- **Integration:**
  - the pack holds the right showtimes and tickets for the member's venues, and no personal details;
  - changes after a refund, a scan elsewhere, and a cancelled showtime;
  - an upload recorded once when sent twice, and concurrently from two server copies;
  - each exception in §8.3;
  - permissions and tenant isolation (the registry).
- **End to end** (Playwright, `context.set_offline(True)`):
  - online, scan; go offline, scan three (one let in, one already used, one not on the list, let in anyway);
  - come back online: the uploads are recorded, and the exceptions show;
  - two browser contexts offline let the same ticket in: one double entry;
  - the app reloads with no connection (S1);
  - at phone size and desktop size.
- **On real phones,** before the pilot: an Android phone and an iPhone, in airplane mode, at a rehearsal with 200 printed tickets. Measure time per scan, battery use over 3 hours, and upload after reconnecting. Recorded in the runbook.
- **Load:** a pack of 2,000 tickets builds within 1 second on the server and loads on a low-end Android phone within 2 seconds. An upload of 500 scans finishes within 10 seconds.

## 15. Done when

1. With the server stopped, an installed scanner that was online up to the stop lets in valid tickets and refuses used, wrong-showtime and fake ones, with the same words as online.
2. A ticket bought one minute before the outage is on the device.
3. After reconnecting, every offline scan appears once in the showtime's attendance and the audit log, attributed to the right member and time.
4. A ticket let in on two offline devices appears as one double entry; a let-in whose M-Pesa code matches a payment is matched; one that doesn't becomes an exception after 48 hours.
5. The device holds no customer details and no references beyond those waiting to upload (checked by reading its IndexedDB in the e2e test).
6. The runbook "Scanning when we're offline" is followed by someone who didn't write it, on a real phone.
7. `docs/failure-modes.md` rows 1.7, 1.9 and 1.10 are ✅.

## 16. Decisions (owner, 2026-10-31: all as suggested)

| # | Question | Decided |
|---|---|---|
| O1 | Two devices offline on one showtime can let a copied ticket in twice, found afterwards (D4). | Accepted for the pilot, with the "one device per showtime" warning |
| O2 | Who may "let in anyway" someone not on the list? | Any staff member who can scan; every one is a Door exception |
| O3 | Snack pickup codes offline in this phase? | No: after the pilot |
| O4 | iPhones in the pilot, or Android only? | Both, installed to the home screen; Android recommended |
| O5 | How far ahead does a device keep showtimes? | Doors opening within 6 hours |
