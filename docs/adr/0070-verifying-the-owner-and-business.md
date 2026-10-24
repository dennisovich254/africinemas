# ADR-0070: Verifying the owner and the business, privately, before going public

- **Status:** Accepted
- **Date:** 2026-10-24
- **Sub-phase:** P14.4
- **Code:** `core/tenancy/verification.jac`, `core/authz/policy.jac` (`tenant.verification`), `core/reporting/staff_home.jac` (the "Verify your business" step, `setup_of`), `web/backoffice/VerificationSection.jac`, `web/backoffice/PdfDrop.jac` (`images`), `web/backoffice/nav.jac`
- **Tests:** `tests/integration/verification_tests.jac`, `tests/integration/staff_home_tests.jac`, `tests/isolation/registry.jac`, `e2e/verification_tests.jac`, `e2e/home_tests.jac`

## Context
A cinema can't become public until AfriCinemas knows who runs it (threat model §1; architecture §134-§135). Phase 14's model: a verification record per cinema, reviewed in the platform console (14.5).

## Decision
1. **The owner alone.** A new permission, `tenant.verification`, is held only by the owner role, which holds every permission. A tenant admin, who can set up everything else, can't see or change it, and another cinema's staff get "not found". The page is **Verification** in the back office's sidebar. The setup guide's last step, "Verify your business", is done once the cinema has been submitted (or is live).
2. **What we collect** (decided with the owner, 2026-10-24; no selfie with the ID for now):
   - **the owner:** legal name as on their ID, ID or passport number, phone, and photos of the ID's front and back;
   - **the business:** registered name, type (sole proprietor, partnership, limited company), registration number, KRA PIN, premises address, the county permit's expiry date, and the registration certificate, KRA PIN certificate and county business permit.

   The ID number is checked by a person: the government register (IPRS) isn't open to us. The phone is confirmed by SMS once there's an SMS provider.
3. **Checked on the server, every problem at once.**
   - **Formats:** the KRA PIN is a letter, nine digits and a letter (kept in capitals). The ID or passport number is 6 to 12 letters and digits. The phone is a Kenyan number, kept as `+254…`. The permit's expiry is a real date.
   - **Text:** plain text only, within length limits.
   - **Drafts:** empty fields are fine while drafting. What's missing is listed for submitting.
4. **Files are private.** Each file is either a photo or a PDF:
   - a photo (JPEG, PNG or WebP) is re-encoded as a clean WebP, as home-page photos are;
   - a PDF is rebuilt from its pages (ADR-0069).

   Files are stored under random names in a `verification` folder in the cinema's media, and served only through `verification_file`: to the owner here, and to platform reviewers in 14.5. They're never served from a public URL.
   - **Phones:** the drop box accepts photos, so a phone offers its camera. A photo over 4 MB is made smaller in the browser first, to at most 2400 pixels a side as a JPEG, because phone cameras take large ones and mobile data is dear.
5. **Submit for review** needs:
   - every detail and file;
   - a county permit that hasn't expired;
   - the owner's email confirmed (14.2);
   - the go-live essentials (§135): a venue, a screen with a published seat layout, prices, and the required policies (14.3b).

   What's missing comes back as a list, with links to where each essential is done. Submitting moves the cinema from `configuring` to `ready_for_go_live` and the record to `submitted`. Nothing can then be changed until a reviewer answers (14.5), and the cinema stays private until it's approved.
6. **How long files are kept** (decided with the owner, 2026-10-24). The page's notice says so, and 14.5 does the deleting, since it brings approval:
   - **ID photos:** deleted 90 days after approval; the date they were checked stays.
   - **Business documents:** kept while the cinema is on AfriCinemas, deleted a year after it leaves.
   - **Support screenshots:** deleted 90 days after the request is closed.

## Consequences
- 14.5 reads the same record and files (`record_of`, `file_answer`) for the reviewer, sets `approved` / `changes_requested` (reasons shown on this page, which becomes editable again) / `rejected`, and runs the retention jobs.
- Every save, upload and submission is in the cinema's audit log (`verification.*`).
