# Data protection impact assessment: verifying cinemas

**Draft v0.1, 2026-10-26. For review by a Kenyan advocate. Internal; may be published
(reg 52(4)).** Follows the template in the Third Schedule of the Data Protection
(General) Regulations, 2021 (reg 50(1)), and section 31(2) of the Data Protection Act,
2019. The legal basis of each point is in [law-register.md](law-register.md).

## Part 1: Description of the processing

| | |
|---|---|
| **Data controller** | [AfriCinemas Limited], [postal address], [privacy@africinemas.co.ke], [phone] |
| **Project** | Verifying cinema owners and businesses before a cinema can sell (P14.4, P14.5; ADR-0070) |
| **Reviewed by** | [Data protection contact], every [12] months, and before any change to what's collected (reg 49(1)(d)) |

### 1. Is a DPIA needed?

Yes. Regulation 49(1) lists processing taken to be high-risk. Verification touches:

- **(e) sensitive personal data**, possibly: an ID document or business record may
  reveal "property details" or "family details" (s.2), and a passport may show
  nationality. We don't set out to collect sensitive data, but we can't rule it out;
- **(i) innovative use of technology**: an online platform deciding which businesses
  may take the public's money;
- **(j)** it decides whether a business may trade on the platform, which significantly
  affects the owner.

It isn't **(c) biometric data**: section 2 defines biometric data as data "resulting
from specific technical processing" of physical characteristics. We store photos of
an ID for a person to look at; we don't extract a face template or compare faces, and
there's no selfie (owner's decision, 2026-10-24). If face matching were ever added, this
assessment would have to be redone first.

### 2. What the project does

Before a cinema's storefront goes live and takes customers' money, a person at
AfriCinemas checks that a real, identifiable owner and a real, permitted business stand
behind it. It protects customers from fake cinemas, protects real cinemas from being
impersonated, and lets a storefront show "Verified by AfriCinemas".

### 3. The personal data

| About | Data |
|---|---|
| The owner | Legal name as on the ID; ID or passport number; phone number; photos of the ID's front and back; email address (already on their account, confirmed) |
| The business | Registered name; type (sole proprietor, partnership, limited company); registration number; KRA PIN; registration certificate; KRA PIN certificate; county business permit and expiry; premises address. For a sole proprietor, these are the owner's personal data too |
| The review | The reviewer's identity, decision, date and notes |

### 4. The information flow

1. **Collection.** The owner fills in the **Verification** page in their back office
   and uploads files from their phone or computer (s.28: from the person directly).
   The page says why each item is asked for and how long it's kept (s.29). Only the
   owner's role holds `tenant.verification`; no other staff member can see or change
   it.
2. **Checking the files.** Each file must be an image or a PDF within a size limit.
   Images are re-encoded and PDFs rebuilt from their pages, removing hidden content
   and metadata.
3. **Storage.** Files are kept under random names in the cinema's private media, never
   at a public address, served only through `verification_file` to the owner and to
   AfriCinemas reviewers, after their sign-in is checked. Details are in the database.
   Location: [the hosting provider and country chosen in P17.3].
4. **Review.** A reviewer with the platform permission sees the submission in the
   console, approves it or asks for more (P14.5). Every view and decision is in the
   platform audit log.
5. **Use after approval.** The cinema's verified date shows on its storefront and the
   public check page (`/verified/<slug>`), which shows the cinema's name and the date,
   **never** the owner's details or documents.
6. **Deletion** (owner's decisions, 2026-10-24), by the scheduled retention job
   (P14.5b, ADR-0072):
   - ID photos: **90 days after approval** (or after the application is refused or
     withdrawn);
   - business documents and details: **while the cinema is active, and one year after
     it closes**.
7. **Transfers.** None outside Kenya, unless the hosting chosen in P17.3 is outside
   Kenya; then s.48, s.49 and regs 40 to 42 apply (Part 2).
8. **Scale.** One owner per cinema: [tens] in the pilot, [hundreds] in the first years.

### 5. How it meets the principles (s.25)

| Principle | How |
|---|---|
| Lawful, fair, transparent | One basis (legitimate interests, Part 2); the page explains each item before collecting |
| Explicit purpose, no other use | Used only to verify, prevent fraud, and answer for the decision; never for marketing |
| Minimal | We ask for what a reviewer needs to tie a person to a permitted business, and no more: no selfie, no date of birth field, no next of kin |
| Accurate | The owner enters and can correct details until submitting; the permit's expiry is tracked |
| Not kept longer than needed | Fixed periods, deleted automatically |
| Not transferred out of Kenya without safeguards | Part 2 |

## Part 2: Necessity and proportionality

| | |
|---|---|
| **Lawful basis** | **Legitimate interests** (s.30(1)(b)(vii)): AfriCinemas' and the public's interest in only letting real, identifiable, permitted businesses take customers' money through the platform. **Balancing:** the owner expects to be checked when opening a business that takes payments online; the data is what they'd show a bank or landlord; the risks are reduced by the measures in Part 3; the processing isn't "unwarranted" given the harm a fake cinema could do. We don't rely on consent, because a cinema can't go live without verification, so consent wouldn't be freely given (s.32(4)) |
| **Consent methods** | Not relied on. [If sensitive data goes outside Kenya, s.49(1) needs consent and safeguards: see "Cross-border" below] |
| **Is the data key to the purpose?** | Yes. Without a tie between a real person, a real business and a permit, "verified" would mean nothing, and fraudulent cinemas could take money |
| **Another way, with less data?** | Considered: (a) M-Pesa paybill name only: shows a paybill exists, not who's responsible or that the business is permitted; (b) business documents only: a stolen certificate would pass; (c) a selfie with the ID: more certain, but more intrusive (and close to biometric), so not done. The owner's ID plus business documents is the least that works |
| **Quality and minimisation** | Fields checked on the server; KRA PIN format checked; files re-encoded; nothing beyond the list in Part 1 |
| **Telling people** | The Verification page's notice (s.29), and the [privacy policy](privacy-policy.md#32-verifying-a-cinema) |
| **Rights** | The owner can see everything they submitted on the page; correct it (before submitting, and by asking afterwards); ask for erasure, which ends the verification and the cinema's ability to sell; requests follow [data-requests-procedure.md](data-requests-procedure.md) |
| **Parties and roles** | AfriCinemas: controller. Hosting provider: processor under a written contract (s.42; reg 24) |
| **Compliance by the parties** | The processor's contract with reg 24(2)'s particulars; the provider's security certifications reviewed in P17.3 |
| **Safeguards** | Part 3 |
| **Cross-border** | [To decide in P17.3.] Preferred: keep verification files in Kenya, or in a country taken to have safeguards under reg 42 (one that has ratified the AU Convention on Cyber Security and Personal Data Protection), so that, if any file turns out to contain sensitive data, s.49's consent question doesn't arise. Otherwise: a reg 41 assessment, documented, and [the advocate's view on whether s.49 consent is needed] |

## Part 3: Risks and measures

Impact and likelihood are each scored 1 (low) to 5 (high); the score is impact ×
likelihood. "Current" is with the measures already built; "after" is with the further
actions.

| # | Risk | Consequence | Owner | Current controls | Current score | Further actions | Score after |
|---|---|---|---|---|---|---|---|
| R1 | **Unauthorised access to ID photos** (an attacker, a misconfigured file store) | Identity theft; fraud in the owner's name; notifiable breach (reg 37: name and ID number) | Engineering lead | Private files, served only through a signed-in endpoint; random names; never a public URL; isolation tests on every endpoint; scrypt passwords | 5 × 2 = 10 | Encrypt verification files at rest with a separate key (done 2026-10-29, ADR-0089); an outside penetration test (P17.5); alerts on unusual file access (P16) | 5 × 1 = 5 |
| R2 | **A reviewer misuses access** (copies documents) | As R1 | Operations lead | Only reviewers hold the permission; every view and decision in the platform audit log | 5 × 1 = 5 | Confidentiality agreements; training; quarterly review of the audit log; two-person access for bulk exports (none exist) | 5 × 1 = 5 |
| R3 | **Data kept too long** | Larger harm from any breach; breaks s.39 | Data protection contact | Retention job deletes on schedule (P14.5b), idempotently | 3 × 2 = 6 | A monthly check that nothing past its date remains; report in the console | 3 × 1 = 3 |
| R4 | **A stolen owner account** submits or reads verification | Owner's documents exposed; a fake cinema verified | Engineering lead | Email confirmed before submitting; only the owner role | 4 × 3 = 12 | Signing out everywhere on password change (P17.5, JI-059); optional second factor for owners [P17.5]; notify the owner by email when verification is viewed or changed (done 2026-10-29, ADR-0089) | 4 × 2 = 8 |
| R5 | **Forged documents** pass review | Customers defrauded by a fake cinema | Operations lead | A person reviews; the business permit's expiry is checked; the paybill's registered name must match the business (P15.3) | 4 × 2 = 8 | A reviewer checklist; check the business on the Business Registration Service and KRA PIN checker where available; suspension (P15.5) | 4 × 1 = 4 |
| R6 | **Sensitive data collected without meaning to** (a document showing family details) | s.44 to s.49 apply; consent needed abroad | Data protection contact | Only the listed documents asked for | 3 × 2 = 6 | Guidance on the page: "cover anything not asked for, such as family details"; keep files in Kenya or a reg 42 country (P17.3) | 3 × 1 = 3 |
| R7 | **Transfer outside Kenya without a basis** | Breaks s.48; fines (s.63) | Engineering lead | None yet (hosting not chosen) | 3 × 3 = 9 | Choose hosting in P17.3 with this DPIA; document the transfer (reg 41(2)) | 3 × 1 = 3 |
| R8 | **The owner can't exercise their rights** | Breaks s.26; complaint to the Commissioner | Data protection contact | The owner can see their submission | 2 × 2 = 4 | The [data requests procedure](data-requests-procedure.md), with its deadlines tracked | 2 × 1 = 2 |
| R9 | **A wrong refusal** stops a real business trading | Loss to the owner | Operations lead | A person decides, with reasons the owner sees; the owner can resubmit | 3 × 2 = 6 | An appeal to a second reviewer; reasons recorded | 3 × 1 = 3 |

## Part 4: Consultation with the Data Commissioner

Section 31(3) needs prior consultation if high risk remains after the measures. With
the further actions, no risk scores above 8, so we don't expect to need it.

**But** section 31(5) says "the data impact assessment reports shall be submitted sixty
days prior to the processing of data". [Advocate: does this require us to submit this
DPIA to the Commissioner 60 days before the first real cinema is verified? If so, it
fixes the earliest date of the pilot (P17.8). Reg 52(3): with no answer within 60 days
of submission, processing may start.]

## Part 5: Sign-off

| Item | Description | Notes |
|---|---|---|
| Measures approved by | [Name, role] | [Date] |
| Remaining risk approved by | [Name, role] | [Date] |
| Advocate's review | [Name, firm] | [Date] |
| Consultation with the ODPC | [Submitted on / not required, with reasons] | s.31(3), s.31(5) |
| Kept under review by | [Data protection contact] | Every [12] months, and before any change to verification |
