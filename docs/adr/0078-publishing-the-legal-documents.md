# ADR-0078: Publishing AfriCinemas' legal documents

- **Status:** Accepted
- **Date:** 2026-10-26
- **Sub-phase:** P15.0b

## Decision

The owner decided on 2026-10-26 to publish version 0.1 of the four public documents
**before the advocate's review**:
- the terms of use;
- the privacy policy;
- the cookie and storage notice;
- the cinema agreement.

Every page says "This version is being reviewed by our lawyers and may change."
Until the company is registered, the documents name **AfriCinemas** only, and say that
the company details will be added in a new version. The contacts are help@, privacy@
and legal@africinemas.co.ke.

- **Where the text comes from.** The published text lives in `core/legal/published/`.
  `scripts/publish_legal.py` builds it from the drafts in `docs/legal/`:
  - it drops the draft notices, the notes to the advocate and internal references
    (plan numbers, ADRs, Jac issues);
  - it fills the bracketed choices with the drafts' defaults: courts of Kenya after
    mediation by a CIArb (Kenya Branch) mediator; 14-day invoices; the support response
    times;
  - it removes the booking assistant, since the chat is off.

  We edit the drafts, re-run the script and read the result, never editing the
  published copies by hand.
- **Serving it.** `legal_document(name)` returns the text with its version and the
  date it applies from. It's a public endpoint, and an unknown name isn't found.
- **The page.** `/legal/<name>` on the main site draws the text from its small Markdown
  (`web/legal/legal_text.jac`): headings, paragraphs, lists, tables, bold, code and
  links. It uses React text, never HTML. A link is kept only to another `/legal/` page
  or an `https` address. Wide tables scroll inside their own box, so the page never
  scrolls sideways.
- **The links.**
  - The main site's footer links all four documents.
  - The sign-up page links the terms and the privacy policy. The cinema agreement isn't
    there: sign-up makes a personal account (invited staff too), and the owner accepts
    the agreement when creating a cinema (P15.1).
  - Every storefront's footer links the AfriCinemas terms, privacy policy and cookie
    notice on the main site, whatever the cinema filled in and whatever its design
    (FooterInfo is drawn inside AI footers too).
- **The registrations checklist.** It's in the platform console, for super admins
  (`platform.settings`). There are 16 items, each with the law behind it. Ticking one
  keeps a reference, who ticked it and when, as one permanent claim per item. Every
  tick and untick is in the platform audit log.

## Consequences

- **Accepting the agreement:** a new version of the cinema agreement must be accepted
  again. That's built in P15.1 with the version number used here.
- **Still to build, listed in `docs/legal/README.md`:**
  - the confirmation email naming the terms' version;
  - a test that every browser-storage key is listed in the notice;
  - the KFCB rating in every listing;
  - an 18-or-over declaration;
  - customers' data export and deletion;
  - the requests and breach registers.
- **The risk** of publishing before review is accepted by the owner and stated on
  every page.
