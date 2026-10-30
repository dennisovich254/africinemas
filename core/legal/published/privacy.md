# AfriCinemas privacy policy

## 1. Who we are

**AfriCinemas** (**"we"**). AfriCinemas is being registered as a company in Kenya, and
we're registering with the Office of the Data Protection Commissioner as a data
controller and a data processor. Our company details and registration number will be
added here.

**Data protection contact:** privacy@africinemas.co.ke.

## 2. Two roles: whose data this policy covers

AfriCinemas runs a booking platform that cinemas use for their websites (their
**storefronts**), box offices and back offices.

- **When you book at a cinema**, the **cinema** decides how your booking data is used:
  it's the **data controller**, and **its own privacy policy** (linked from its
  storefront's footer) tells you about it. AfriCinemas processes that data **for the
  cinema, as its data processor**, only on its instructions, under a written contract
  (Data Protection Act, s.42). We never use it for our own marketing, never share it
  with other cinemas, and never sell it.
- **This policy** covers the data AfriCinemas uses for its **own** purposes, as **data
  controller**: the accounts of cinema owners and staff, verifying cinemas, billing,
  support, our own team, and keeping the platform secure. It also explains, in
  section 3.7, the few things we do with customers' data as controller.

## 3. What we collect, why, and on what basis

We use one lawful basis for each purpose (General Regulations, reg 5), from section 30
of the Data Protection Act.

### 3.1 Cinema owners and staff

| What | Why | Lawful basis (s.30) |
|---|---|---|
| Email address, password (stored only as a scrypt hash), the name you set on Your profile | To give you a sign-in and show your colleagues who did what | Performance of a contract (the cinema agreement; for staff, the cinema's instruction to give you access): s.30(1)(b)(i) for the owner, legitimate interests s.30(1)(b)(vii) for staff |
| Your role, venue, invitations, and when your shifts start and end | To give you only the access your job needs, and to end access when you sign out | Legitimate interests: security of the cinema's sales |
| What you do in the back office (the audit log: who changed what, when) | So the cinema can see who did what, and to investigate problems and fraud | Legitimate interests |
| Email confirmation codes and links | To check the email is yours | Legitimate interests (security) |

### 3.2 Verifying a cinema

| What | Why | Lawful basis |
|---|---|---|
| The owner's legal name, ID or passport number, phone, and photos of the ID's front and back | To confirm that a real, identifiable person is responsible for the cinema before it can take customers' money, and to prevent fraud and impersonation | Legitimate interests: protecting customers and the platform from fraudulent cinemas (s.30(1)(b)(vii)); weighed in our impact assessment |
| The business's registered name, type, registration number, KRA PIN, registration certificate, KRA PIN certificate, county business permit and its expiry, premises address | To confirm the business exists, is the one named, and is allowed to trade | As above |
| The reviewer's decision and notes | To record why a cinema was approved or asked for more | As above |

We collect these from the owner directly (s.28). **Giving them is voluntary, but a
cinema can't go live without them** (s.29(g), (h)). We **don't** take a selfie or
compare faces, and we don't use the photos for anything but this check.

### 3.3 Billing

| What | Why | Lawful basis |
|---|---|---|
| The cinema business's name, KRA PIN, address, its order totals and our fees, statements, invoices and payments to us | To invoice our fee and keep tax records | Legal obligation for tax records (Tax Procedures Act, 2015, s.23): s.30(1)(b)(ii); contract for invoicing |
| The M-Pesa number and name on payments to our paybill | To match payments to invoices | Contract |

### 3.4 Support

| What | Why | Lawful basis |
|---|---|---|
| Your messages with our support team, and any screenshots you attach | To help you | Contract (owner) / legitimate interests (staff) |

Please never include passwords, PINs or card numbers in a support message.

### 3.5 Our own team

Names, emails, roles and actions of AfriCinemas' own staff in the platform console, for
access and accountability. Lawful basis: contract of employment and legitimate
interests.

### 3.6 Keeping the platform working and secure

| What | Why | Lawful basis |
|---|---|---|
| Technical records of requests: time, address requested, the account, errors | To run, debug and secure the platform, and detect attacks | Legitimate interests |
| What's kept in your browser | See the [cookie and storage notice](/legal/cookies) | As stated there |

### 3.7 Customers' data: what we do as controller

Almost everything about a booking is done for the cinema (section 2). As controller, we
only:

- use order **totals** to calculate our fee to the cinema (no personal data is needed
  for this, and invoices show totals, not customers);
- use technical records and booking patterns to **detect fraud and attacks** on the
  platform as a whole (legitimate interests);
- keep records the law requires of us.

### 3.8 AI designs

We use AI from Anthropic to design cinemas' storefronts. It's given the cinema's brand
details only (its name, logo and colours), never anyone's personal data.

## 4. Who receives it

We share personal data only with:

| Who | What for | Where |
|---|---|---|
| The cinema concerned | Its own customers' and staff's data, which is its data | Kenya |
| Our hosting provider | Servers, database, files and backups | Named here before we take real bookings |
| Our email provider | Sending emails | Named here before we take real bookings |
| Anthropic, PBC | Generating storefront designs from a cinema's brand details (no personal data) | United States |
| Safaricom PLC | M-Pesa payments (for customers' payments, the cinema's own contract with Safaricom; for our invoices, ours) | Kenya |
| KRA | Invoices through eTIMS, and tax returns | Kenya |
| Our professional advisers, auditors and insurers | Under a duty of confidentiality | Kenya |
| The police, courts and regulators | Only where the law requires it, or to establish or defend legal claims | Kenya |
| A buyer of AfriCinemas' business | If that ever happens, bound by this policy | — |

Each service provider processes data only on our instructions, under a written
contract (s.42(2); reg 24).

## 5. Outside Kenya

Some of our providers are outside Kenya (section 4). Before transferring personal data
out of Kenya we establish the basis (reg 40): appropriate safeguards in a binding
contract, essentially equivalent to Kenyan law (s.48(a); reg 41), or a country taken
to have such safeguards (reg 42).
We record each kind of transfer (reg 41(2)) and can show it to the Data Commissioner.
**We don't transfer sensitive personal data outside Kenya** (s.49).

## 6. How we protect it

Our measures (s.29(f); s.41) include:

- every request checked for the cinema it's for, with automated tests on every endpoint
  so one cinema can never reach another's data;
- roles giving each person only the access their job needs; shifts that end when you
  sign out; an audit log;
- encryption on every connection (HTTPS); M-Pesa keys encrypted at rest; passwords
  stored only as hashes;
- verification documents and support images kept private and served only to the
  people allowed to see them, never at a public address;
- automatic deletion when data reaches the end of its retention period;
- backups, monitoring, and an outside security test before launch.

**A known limit, told openly:** changing your password doesn't yet sign you out on your
other devices. Sign out on them yourself. We'll fix this before launch.

## 7. How long we keep it

We keep personal data only as long as needed (s.39; reg 19), then delete or anonymise
it. Our retention schedule, reviewed every 12 months:

| Data | Kept for | Why that long |
|---|---|---|
| ID photos (front and back) | **90 days after the cinema's verification is approved** (or after the application is refused or withdrawn) | Long enough to answer questions about the decision |
| Business documents | **While the cinema is on AfriCinemas, and one year after it closes** | To show the cinema was verified while it traded |
| Owner's verification details (name, ID number, phone) | As business documents | As above |
| Support screenshots | **90 days after the request is closed** | To follow up |
| Support messages | 2 years after the request is closed | To learn from repeated problems |
| Staff and owner accounts | While the account is in use; 12 months after it's removed from every cinema | So people can be invited back, and for investigations |
| Audit log | 6 years | Claims on a contract can be brought within six years (Limitation of Actions Act) |
| Billing: statements, invoices, payments | 6 years | Tax law (Tax Procedures Act, s.23) |
| Order and payment records (for the cinema) | As the cinema instructs, and at least 5 years | Tax law |
| Technical request records | 90 days | Debugging and security |
| Email confirmation codes | Until used or expired | — |
| Backups (encrypted copies of all of the above) | **35 days**, then deleted; so data deleted from AfriCinemas is gone from every backup within 35 days | To recover after a failure or an attack |

## 8. Your rights

Under the Data Protection Act (s.26 and s.34 to s.40) you have the right to:

- **be told** how your data is used (this policy);
- **see** your data and get a copy: we answer **within 7 days**, free (reg 9);
- have wrong, out-of-date or incomplete data **corrected**: within **14 days** (reg 10);
- have data **deleted** where it's no longer needed, unlawful, or you withdrew consent:
  we answer **within 14 days** (reg 12), except what the law requires us to keep;
- **restrict** our use of it, or **object** to it: within **14 days** (regs 7 and 8);
  your objection to direct marketing always succeeds;
- get your data in a **machine-readable** form, or have it sent to another provider:
  within **30 days** (s.38; reg 11);
- **withdraw consent** where we rely on it, at any time (s.32), without affecting what
  was done before;
- not be subject to a decision based only on automated processing that significantly
  affects you (s.35). We don't make any: verification is decided by a person.

**How to ask:** write to privacy@africinemas.co.ke, or use the regulator's forms
(DPG 1 to DPG 5 in the First Schedule of the General Regulations). We'll check it's you
before answering. It's free, except a reasonable fee for portability (reg 11). If we
can't do what you ask, we tell you why in writing.

**Your data at a cinema** (your bookings, your account there): ask the cinema; it's
the controller. If you ask us, we pass your request to the cinema within 2 working
days and help it answer.

**To complain:** contact us first if you can. You may also complain to the **Office of
the Data Protection Commissioner** at any time (s.56), through its website, odpc.go.ke. The Commissioner concludes a complaint within 90 days.

## 9. Children

AfriCinemas is for adults: you must be 18 to create an account or pay. Children come to
the cinema on bookings made by a parent or guardian. We don't knowingly collect a
child's data. If we learn we have, without a parent's or guardian's consent (s.33), we
delete it. We never profile children for marketing (reg 13(2)(b)). The criteria
(reg 23(2)(g)): an account or payment needs a declaration that the person is 18 or
over; nothing else is asked about children.

## 10. Marketing

**AfriCinemas doesn't send customers marketing**, and no cinema can send you offers
through AfriCinemas.

A cinema may choose to send its own offers. If it does, its checkout, sign-up page and
My account show a box to ask for them, never ticked for you. We record your choice for
that cinema (when, and where you made it), and the cinema sends its offers itself,
under its own privacy policy. You can withdraw at any time on **My account** at that
cinema, or by telling the cinema; your objection to marketing always succeeds (reg 8).

We may email cinema owners about AfriCinemas' own services; they can stop these at any
time from the email.

## 11. Changes to this policy

Each version has a number and the date it applies from. We tell account holders about
important changes by email before they apply.
