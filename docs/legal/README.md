# AfriCinemas' legal documents (P15.0)

**Status: drafts v0.1, 2026-10-26, for review by a Kenyan advocate. Nothing here is
published or in force until the advocate approves it.** These are drafts written by
the team, not legal advice.

Every legal point is anchored to a Kenyan law, with its section, in the
[law register](law-register.md). The register also says how each citation was checked:
read in the official text, taken from a law firm's summary, or still to be confirmed.

## The documents

| Document | For | Published at | Accepted how |
|---|---|---|---|
| [The cinema agreement](cinema-agreement.md), with schedules: 1 the fee, **2 the data processing agreement**, 3 support and service levels, 4 acceptable use | Each cinema (the contract with AfriCinemas) | `africinemas.co.ke/legal/cinema-agreement` | Ticked and accepted in the back office, versioned (P15.1) |
| [Terms of use](terms-of-use.md) | Visitors and customers | `africinemas.co.ke/legal/terms`; every footer | Paying or creating an account, with the notice beside the button (P14.3c) |
| [Privacy policy](privacy-policy.md) | Everyone, for AfriCinemas' own data | `africinemas.co.ke/legal/privacy`; every footer | Read, not accepted |
| [Cookies and storage](cookies-and-storage.md) | Everyone, for every AfriCinemas site and storefront | `africinemas.co.ke/legal/cookies`; every footer as **Cookies and storage** | Read, not accepted (nothing optional is stored) |
| [DPIA: verifying cinemas](dpia-verification.md) | The team and the ODPC | Internal; may be published (reg 52(4)) | Signed off |
| [Breach procedure](breach-procedure.md) | The team (P16.8's runbook) | Internal | — |
| [Data requests procedure](data-requests-procedure.md) | The team | Internal | — |
| [Registrations checklist](registrations-checklist.md) | The owner | The platform console (P15.0b) | Each item ticked, with who and when |
| [Questions for the advocate](questions-for-advocate.md) | The advocate | — | — |

## How to review them

1. The advocate reads the [questions](questions-for-advocate.md) first: the first four
   could change the launch plan.
2. Then the [law register](law-register.md), checking the "Secondary" and "To confirm"
   entries, and for amendments.
3. Then each document. Words in [square brackets] are details to fill in or decisions
   to make.
4. The approved versions are numbered 1, with the date they apply from, and recorded
   in the console's checklist (item 14).

## What the drafts need from the product (P15.0b and after)

Found while drafting. Each is small, and listed so it isn't lost:

- **Publish the documents** at `/legal/...`, each with its version and date, linked
  from the main site's footer, the sign-up page, and every storefront's footer
  (**Cookies and storage** included); a new version of the cinema agreement must be
  accepted again (P15.1).
- **The registrations checklist** in the console.
- **The confirmation email names the version of the terms agreed**, with a link
  (Consumer Protection Act, s.32).
- **A test that every browser-storage key is listed** in the cookie notice.
- **The KFCB rating wherever a film is listed** (Films and Stage Plays Act, s.17(3)):
  check every listing, card, chat card and email.
- **An 18-or-over declaration** at sign-up and payment (Data Protection Act, s.33).
- **The verification page's guidance** to cover anything not asked for, such as family
  details, on uploaded documents (DPIA R6).
- **Verification files encrypted at rest** with a separate key, and the owner emailed
  when their verification is viewed or changed (DPIA R1, R4; P17.5).
- **Customers' "Download my data" and "Delete my account"**, so cinemas can answer
  requests within the regulations' deadlines.
- **A requests register and a breach register** in the console (s.43(8)).
- **Where data is stored** (P17.3): verification files in Kenya or a reg 42 country.

## Already decided by the owner

- No tracking without a consent banner first (2026-10-24).
- Retention: ID photos 90 days after approval; business documents while active and a
  year after closing; support screenshots 90 days after the request closes; no selfie
  (2026-10-24).
- The verified badge is plain text; the check page is at `/verified` (2026-10-24).
- The fee: 10% of the order total, invoiced monthly, not refunded on refunds,
  suspension by a person only (plan P15.1 to P15.5).
