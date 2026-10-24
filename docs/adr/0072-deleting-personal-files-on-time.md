# ADR-0072: Deleting personal files on time

- **Status:** Accepted
- **Date:** 2026-10-24
- **Sub-phase:** P14.5b
- **Code:** `core/tenancy/retention.jac`, `core/tenancy/verification.jac` (`remove_files`, `files_removed`), `core/support/requests.jac` (`drop_old_screenshots`), `core/tenancy/models.jac` (`Tenant.closed_at`), `web/platform/ReviewPages.jac`, `web/support/SupportThread.jac`
- **Tests:** `tests/integration/retention_tests.jac`

## Context
Kenya's Data Protection Act, 2019 says personal data is kept no longer than needed. The owner set the periods before 14.4 (2026-10-24), and the Verification page's notice states them.

## Decision
1. **The periods:**
   - **ID photos:** 90 days after the cinema's verification is approved. The approval's date and reviewer stay, as the record that the ID was checked.
   - **Business documents** (registration certificate, KRA PIN certificate, county permit): kept while the cinema is on AfriCinemas, deleted a year after it starts closing. `Tenant.move_to` now records when a cinema starts closing (`closed_at`), and clears it if the cinema comes back.
   - **Support screenshots:** 90 days after their request was closed. The written conversation stays.
2. **One job, on every server copy, every 6 hours** (`AFRICINEMAS_RETENTION_SECONDS`).
   - **How:** it runs `retention_due(now)` over every cinema. Deleting is idempotent, so two copies at once only find less to do.
   - **The decision is separate from the clock:** `retention_due(at)` takes the time as an argument, so tests run it as of any date (`t_retention`).
3. **Deletions are noted where the file was:** the verification record's `files_removed` (item → when), and a message's `image_removed_at`.
   - **The reviewer's page** shows "Deleted <date>, as our retention rules say" instead of "Not sent".
   - **The support thread** shows "Screenshot deleted 90 days after this request closed".
4. **No cinema closes yet.** No endpoint closes one today, so the business-document rule takes effect once closing exists. The test closes a cinema through a test-only hook.

## Also in 14.5b
- **The Verified badge in listings:** `public_cinemas` carries each cinema's `verified_at`. The booking assistant's `find_cinemas` is told what it means.
- **Trailers:** Vimeo trailers play with do-not-track (`dnt=1`). The Play trailer button says which service plays the trailer and that it may set its own cookies, ahead of the cookie and storage notice (15.0).
