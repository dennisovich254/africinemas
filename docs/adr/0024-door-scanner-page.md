# ADR-0024: The door scanner is a back-office page with an injectable QR decoder and a typed-reference fallback

- **Status:** Accepted
- **Date:** 2026-10-08
- **Sub-phase:** P6.4
- **Code:** `web/backoffice/ScannerSection.jac`, `core/booking/redeem_api.jac` (`door_showtimes`, `door_is_open`), `core/catalog/venues.jac` (`screenings_of_cinema`)
- **Tests:** `tests/integration/door_showtimes_tests.jac`, `e2e/scanner_tests.jac`

## Context
Architecture §48: a scanner works for a selected showtime, scans QR codes and redeems them atomically. 6.2 made redeeming (`redeem_ticket`, with its door window). Plan 6.4 asks for camera scanning through an npm library with manual entry as a fallback. Its tests are the manual-entry flow end to end, and the camera component tested with an injected decoder.

## Decision
1. **The back office's Scanner section** (`/app/<slug>/scanner`, permission `tickets.scan`) is the scanner, so any staff device that can sign in can scan. There are no separate scanner devices yet (§48's device registry comes later).
2. **`door_showtimes(tenant)` (login only, on shift)** lists the published showtimes whose door is open now, at the venues where the caller may scan.
   - It uses `door_is_open`, the same window `redeem_ticket` enforces: from 120 minutes before the start until `ends_at`.
   - Staff without `tickets.scan` anywhere are refused.
   - With one showtime open, the page chooses it.
3. **The camera** starts only when asked and stops when the showtime or the page changes.
   - It reads codes through a decoder object: `available() -> Promise<bool>` and `start(video, on_code) -> Promise<stop>`.
   - The real decoder wraps `qr-scanner`, using the browser's built-in barcode reader where available and the rear camera.
   - A page given `window.__africinemasDecoder` uses that instead. This is how the browser tests drive the scan → redeem → result path without a camera.
4. **One code, one check.** A code the camera reads again within 4 seconds isn't sent again, so a ticket held up counts once. A typed reference is always checked.
5. **The result card** says Admit with the seat, or the refusal in words: already used (when and by whom), wrong showtime (which), too early (when the doors open), cancelled, refunded, not a ticket, or unknown.
   - It has an icon and a heading as well as green or red, and is announced politely.
   - Phones vibrate: short for admit, a double pulse for refused.
6. **Manual entry is always there**, below the camera, and is the fallback when there's no camera or permission is refused.

## Consequences
- **The test hook (`window.__africinemasDecoder`)** stays in production code. It only changes how codes are read, never what the server accepts: every code is still redeemed and checked by the server.
- **No offline scanning** (§49) and no scanner device accounts yet.
