# ADR-0089: Verification files sealed at rest, and owners told of views and changes

- **Status:** Accepted
- **Date:** 2026-10-29
- **Sub-phase:** P15.0 (DPIA R1, R4)

## Context

An owner's ID photos and the business's certificates are the most sensitive data we
hold: a leak of a name with an ID number is a notifiable breach (reg 37). The
verification DPIA lists two further measures:
- **R1:** encrypt the files at rest with a separate key;
- **R4:** tell the owner by email whenever their verification is viewed or changed, so
  a stolen account or a misused review is noticed.

## Decision

- **Sealed at rest** (`core/tenancy/file_box.jac`):
  - Each uploaded file is AES-256-GCM-sealed before it reaches the file store.
  - The key is derived from `AFRICINEMAS_FILES_KEY`, an environment secret apart from
    the M-Pesa keys' one, never in the database or the file store.
  - Each file is bound to its cinema, document and storage key, so a sealed file moved
    elsewhere won't open.
  - The verification record notes `sealed: "v1"`. Files stored before this (none in
    production) are read as they are.
  - Without the secret, uploading is refused rather than storing a file in the clear.
- **Owners told** (`core/tenancy/verification_notice.jac`): every owner is emailed:
  - "changed", when the details are saved, a document is uploaded, or it's submitted;
  - "viewed", when AfriCinemas staff open a document.

  At most one of each kind an hour per cinema, so one review sends one email. The
  platform audit log still has every view.

## Consequences

- `AFRICINEMAS_FILES_KEY` must be set and backed up with the deployment secrets
  (`docs/before-go-live.md`). Losing it makes the uploaded documents unreadable. Owners
  would then upload them again.
- The owner viewing their own documents sends no email.
