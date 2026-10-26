# The AfriCinemas cinema agreement

**Draft v0.1, 2026-10-26. For review by a Kenyan advocate. Not legal advice and not in
force.** Words in [square brackets] are details to fill in or decisions to make. Each
clause's legal basis is in [law-register.md](law-register.md).

This agreement is between:

- **[AfriCinemas Limited]**, a company registered in Kenya under the Companies Act, 2015
  with number [number], of [registered office], KRA PIN [PIN] (**"AfriCinemas"**,
  **"we"**); and
- **the cinema business** named when the agreement is accepted (**"the Cinema"**,
  **"you"**), acting through its owner.

You accept it in the back office before your cinema can sell tickets: by ticking that
you've read it and pressing **Accept**, which we record with the version, the date and
time, and the account that accepted (P15.1). A contract formed this way is valid
(Kenya Information and Communications Act, s.83J). The person accepting confirms they
are authorised to bind the Cinema.

## 1. What the words mean

- **The Platform**: AfriCinemas' software and services: the back office, the
  storefront, the box office, the door scanner, the snack counter, the booking
  assistant, reports and support.
- **The Storefront**: your cinema's public website on the Platform, at
  `<your-slug>.africinemas.co.ke` and any address you connect to it.
- **Customer**: a person who books, buys from, or creates an account at your
  Storefront, or buys at your box office through the Platform.
- **Order**: a booking or purchase of tickets, snacks, 3D glasses or other items
  through the Platform, online or at your box office, whether paid by M-Pesa or cash.
- **Order Total**: everything the Customer pays for an Order, including tickets,
  snacks, glasses and your own booking fee, before any refund.
- **Fee**: AfriCinemas' fee for the Platform (clause 5 and schedule 1).
- **Your Content**: everything you or your staff put on the Platform: your name, logo,
  colours, films' details, posters, trailers, photos, prices, policies and texts.
- **Personal Data**, **controller**, **processor** and **data subject** have the
  meanings in the Data Protection Act, 2019.
- **Working day**: a weekday that isn't a public holiday in Kenya.

## 2. What AfriCinemas provides

2.1 We provide the Platform to you and your staff while this agreement lasts:

- a back office to set up venues, screens, seat layouts, films, showtimes, prices,
  snacks, glasses, staff and policies;
- a Storefront where Customers browse, book seats, buy snacks and glasses, and pay by
  M-Pesa, with tickets by email and on their phone;
- a box office for selling at the counter by cash or M-Pesa, a door scanner, and a
  snack counter;
- reports of your takings and stock, and an audit log of who did what;
- a booking assistant on your Storefront, and a connector so Customers may book
  through AI apps they choose to connect;
- AI-generated designs for your Storefront, which you approve before they're used;
- help from our support team through the back office.

2.2 We may improve and change the Platform. We'll tell you at least [14] days before a
change that takes away a feature you use, except where we must act sooner for
security or to comply with the law.

2.3 **Service levels.** We aim for the Platform to be available [99.5]% of each month,
excluding planned maintenance we announce at least [48] hours ahead and outside
[18:00 to 23:00 East Africa Time]. Schedule 3 sets out how we respond to problems. We
publish the Platform's status at [status.africinemas.co.ke] (P16.7).

2.4 We don't guarantee that the Platform will never fail. When it does, we restore it as
quickly as we reasonably can, and keep you told.

## 3. AfriCinemas' role in your sales

3.1 **You are the seller.** Every Order is a contract between you and the Customer,
for your shows, seats, snacks and glasses. We provide the technology on your behalf:
we take bookings and start payments in your name, as your agent for that purpose only.
We don't sell tickets ourselves, and we aren't a party to your contract with the
Customer.

3.2 **Money goes to you.** Customers' M-Pesa payments go straight to your own paybill
or till (clause 4). Cash at your box office is yours. AfriCinemas never holds
Customers' money. [Advocate: confirm this keeps AfriCinemas outside the National
Payment System Act's authorisation requirement, given *KENEX v CBK* (2022); see
questions-for-advocate.md.]

3.3 Our Fee is invoiced to you monthly (clause 5). It isn't taken from Customers'
payments.

## 4. Your M-Pesa

4.1 Before your Storefront goes live, you connect your own M-Pesa paybill or till in
**Settings → Payments**, with the Daraja API keys Safaricom gives you. Only a cinema
verified under clause 7 can connect one, and its registered name must match your
verified business (P15.3).

4.2 Your contract with Safaricom for your paybill or till, its charges and its rules
are between you and Safaricom.

4.3 We store your keys encrypted and never show them again in full. Changing them needs
your password again, waits a cooling-off period, and we email and notify you.

4.4 You keep your paybill or till active, and tell us at once if you think your keys
have been exposed.

## 5. The Fee, invoices and payment

5.1 **The Fee** is the percentage in schedule 1 (today **10%**) of the Order Total of
every paid Order, online or at your box office, by M-Pesa or by cash.

5.2 The Fee is worked out when an Order is paid and fixed on that Order, with the
version of the fee rule that applied. A later change to the fee rule never changes it.

5.3 **Refunds.** When you refund a Customer, the Fee on that Order is not refunded,
because the Platform's work for the Order was done. [Decision for the owner: whether a
refund caused by a Platform failure, or a showtime cancelled by you, should credit the
Fee.]

5.4 **Invoices.** On the 1st of each month we issue a statement of the previous month
(bookings, takings by channel, refunds, Fees, VAT on the Fees when we're registered,
and the amount due) and an invoice with a number, a due date, and how to pay. You see
them on your **Billing** page. Invoices are issued through KRA's eTIMS (Tax Procedures
Act, 2015, s.23 and the Tax Procedures (Electronic Tax Invoice) Regulations).

5.5 **Payment.** You pay each invoice within [14] days, to AfriCinemas' paybill
[number] with the invoice number as the account number, or by bank transfer to
[account]. Payments are matched to invoices automatically.

5.6 **VAT.** The Fee is exclusive of VAT. When AfriCinemas is registered for VAT (Value
Added Tax Act, 2013, s.34), VAT is added at the rate in force.

5.7 **Withholding tax.** If the law requires you to withhold tax from a payment to us,
you give us the withholding certificate within [30] days, and the invoice counts as
paid to the extent of the tax withheld.

5.8 **Late payment.** If an invoice is unpaid on its due date, we remind you, and your
back office shows a notice. If it's still unpaid [30] days after the due date, a person
at AfriCinemas (never an automatic process) may suspend your cinema under clause 12.
[Decision: interest on late payment, and at what rate, if any.]

5.9 **Disputing an invoice.** If you think an invoice is wrong, tell us within [30]
days of receiving it, saying why. You pay the part you don't dispute. We look into it
and answer within [10] working days. A corrected invoice is issued as a credit note;
an issued statement never changes.

5.10 **Changing the Fee.** We may change the Fee by giving you at least [60] days'
notice. A change applies only to Orders paid after the date it takes effect, and only
once you accept the new version of this agreement (clause 16). If you don't accept it,
you may end this agreement under clause 13.2 before the change takes effect, and the
old Fee applies until then.

## 6. Your responsibilities

6.1 **Licences and the law.** You hold, and keep in force, everything the law requires
for your business and your shows, including:

- your registration as an exhibitor with the **Kenya Film Classification Board**, and
  its annual licence (Films and Stage Plays Act, Cap. 222, s.12; the Film Distribution
  and Exhibition Regulations, 2024);
- for every film you show, the Board's **certificate of approval** (s.12(2), s.16),
  shown with any cuts the Board directed;
- your county business permit, and any other licence for your premises, food and
  drink;
- your registrations with the Office of the Data Protection Commissioner, if the
  Data Protection (Registration of Data Controllers and Data Processors) Regulations,
  2021 require them.

6.2 **Age ratings.** You enter each film's KFCB rating correctly. The Platform shows it
wherever the film is listed. You announce it on screen before the film, check ages at
the door, and never admit a child to a film rated for adults only (s.17).

6.3 **Posters and trailers.** You only use posters and trailers that you're entitled to
use and that the Board has approved where the law requires it (s.13).

6.4 **Your shows and your Customers.** You're responsible for:

- holding every show you sell, in the screen and seats you sold, at the time shown;
- your prices, booking fee, snacks and glasses, and their quality (Consumer Protection
  Act, s.5; Sale of Goods Act);
- your terms of sale, refund and cancellation policy, house rules and accessibility
  information, which you publish on your Storefront (P14.3b) and which don't take away
  Customers' rights under the Consumer Protection Act;
- refunds, exchanges and complaints from your Customers, under your policies and the
  law;
- what happens at your premises.

6.5 **Honest content.** Your Content is true and not misleading (Consumer Protection
Act, s.12; Competition Act, 2010, Part VI). Your prices are the full prices. You don't
claim to be AfriCinemas, or that AfriCinemas endorses you, and you don't use the words
"verified" or "AfriCinemas" in your names, or badge claims in your texts, except where
the Platform shows them (ADR-0071).

6.6 **Your staff.** You decide who on your staff has access and what they can do. You
make sure they keep their sign-ins private, use the Platform only for your business,
and follow schedule 2's security duties. You remove anyone who leaves, at once. You're
responsible for what your staff do on the Platform.

6.7 **Cash.** You count and keep the cash taken at your box office. Cash sales are
recorded on the Platform as they happen, and the Fee applies to them.

6.8 **Your marketing.** Offers are off unless you turn them on (in **Website
information**: "We send offers to customers who ask for them"). When they're on, the
Platform shows Customers an unticked box at checkout, at sign-up and on My account, and
records who agreed, when and where, and who withdrew. **AfriCinemas doesn't send your
offers.** You send them yourself, and as the controller of your marketing you're
responsible for it: sending only to Customers whose consent is current, naming your
cinema, and giving a free, simple way to stop in every message (Data Protection Act,
s.37; General Regulations, regs 14 to 17). When a Customer asks you to stop, you stop
within the time the law allows and record it on the Platform.

6.9 **Acceptable use.** You and your staff follow schedule 4.

## 7. Verification

7.1 Before your Storefront can go live, you give us the details and documents asked for
on the **Verification** page (P14.4): the owner's legal name, ID or passport number,
phone and photos of the ID; and the business's registered name, type, registration
number, KRA PIN, registration certificate, KRA PIN certificate, county business permit
and premises address.

7.2 A person at AfriCinemas reviews them and approves your cinema, or asks for more.
Approval lets your Storefront go live and shows "Verified by AfriCinemas" on it. It
means we checked these documents. It doesn't mean we guarantee your shows or your
service.

7.3 You keep the details current. You tell us within [14] days if your business's
name, ownership, registration or permit changes, and upload the new permit before the
old one expires.

7.4 We use these documents only to verify you, to prevent fraud, and to meet our legal
obligations, and keep them only as long as schedule 2 and our privacy policy say (ID
photos: 90 days after approval; business documents: while your cinema is on
AfriCinemas and one year after it closes). Our [DPIA](dpia-verification.md) explains
why and how.

## 8. Your Content and intellectual property

8.1 **Your Content stays yours.** You keep every right in your name, logo, colours,
photos and texts.

8.2 You give AfriCinemas a non-exclusive, royalty-free licence, for as long as this
agreement lasts (and afterwards only as clause 14 allows), to host, copy, adapt (for
example, resize images or re-encode files) and show Your Content on the Platform, your
Storefront, emails to your Customers, and AI apps your Customers connect, only to
provide the Platform.

8.3 You confirm you own, or are licensed to use, Your Content, including posters,
trailers and film images from distributors (Copyright Act, 2001; Trade Marks Act). You
indemnify AfriCinemas against claims that Your Content infringes someone's rights
(clause 11.4).

8.4 **AI designs.** Storefront designs the Platform generates for you, once you've
approved them, are yours to use on the Platform. We don't promise they're unlike
anyone else's; you check that a design suits your brand before approving it.

8.5 **The Platform stays ours.** AfriCinemas owns the Platform, its software, designs,
templates and the AfriCinemas name and marks. This agreement gives you the right to use
them while it lasts, and nothing more. You don't copy, resell, reverse-engineer or
build a competing service from the Platform.

8.6 **Suggestions.** If you suggest improvements, we may use them freely.

8.7 **Showing that you use us.** We may name your cinema, with your logo, as an
AfriCinemas cinema in our marketing. You can tell us to stop at any time.

## 9. Personal data

9.1 **Your Customers' data: you're the controller, we're your processor.** For the
personal data of your Customers and of the people who use your Storefront and your box
office, you decide why it's processed. AfriCinemas processes it on your behalf, only
on your instructions, under the **data processing agreement in schedule 2** (Data
Protection Act, s.42; General Regulations, reg 24).

9.2 **Data we control.** AfriCinemas is the controller of the data it processes for its
own purposes: the accounts of your owner and staff, the verification documents, your
cinema's billing, support conversations with us, the security of the Platform, and
preventing fraud. Our [privacy policy](privacy-policy.md) covers it.

9.3 **No selling, no cross-cinema marketing.** We never sell personal data. We never
use your Customers' data to market another cinema or ourselves. A Customer's account
belongs to your cinema alone (P8.6c).

## 10. Confidentiality

10.1 Each of us keeps the other's confidential information confidential and uses it
only for this agreement. Confidential information includes your takings, your
Customers' data, your keys, our software and our prices to you, and anything marked
confidential.

10.2 This doesn't apply to information that's public (other than through a breach of
this clause), that the receiver already had, or that the law, a court or a regulator
requires to be disclosed. Where the law allows, the one asked to disclose tells the
other first.

10.3 This clause lasts [five] years after this agreement ends, and for Personal Data and
keys, for as long as they're held.

## 11. Liability

11.1 **What isn't limited.** Nothing in this agreement limits liability for death or
personal injury caused by negligence, for fraud, for wilful misconduct, for breaking
clause 10 (confidentiality) or schedule 2 (personal data) [advocate: whether data
protection liability should be capped], or for anything the law doesn't allow to be
limited.

11.2 **No indirect loss.** Neither of us is liable to the other for loss of profit,
revenue, goodwill or data, or any indirect or consequential loss, however it arises.

11.3 **The cap.** Subject to 11.1, AfriCinemas' total liability to you under or in
connection with this agreement, in any 12 months, is limited to the Fees you paid us in
the 12 months before the event giving rise to the claim [advocate: whether a minimum,
such as KES [amount], is needed for the cap to be reasonable].

11.4 **Your indemnity.** You indemnify AfriCinemas against claims by Customers,
distributors, rights holders and regulators arising from your shows, your Content, your
premises, your refunds, or your breach of the law or of this agreement. We tell you
promptly about any such claim, let you conduct its defence, and don't settle it
without your agreement.

11.5 **Our indemnity.** We indemnify you against claims that the Platform itself (not
Your Content) infringes someone's intellectual property in Kenya, on the same
conditions.

11.6 **Things beyond control.** Neither of us is liable for a delay or failure caused
by events beyond our reasonable control: a nationwide power or internet failure, an
M-Pesa outage, a natural disaster, war, civil unrest, an epidemic, or a government
act. The one affected tells the other promptly and does what it reasonably can to
limit the effect. If such an event lasts more than [30] days, either of us may end
this agreement by notice.

## 12. Suspension

12.1 A person at AfriCinemas (never an automatic process) may suspend your cinema, in
whole or in part, if:

- an invoice is unpaid [30] days after its due date, after the reminders in clause 5.8;
- your verification expires (for example, your business permit) or is found to be
  false;
- you seriously break this agreement or the law, for example by selling shows you don't
  hold or films without a KFCB certificate;
- it's needed to protect Customers, the Platform or other cinemas, for example after a
  security incident; or
- a court or regulator orders it.

12.2 While you're suspended, your Storefront shows "This cinema isn't available right
now", new Orders and payments stop, and your back office says why. Your data is kept,
and you can still see your reports and invoices. Customers' existing tickets remain
valid unless the show is cancelled, and you remain responsible for honouring or
refunding them.

12.3 Except where we must act at once (security, fraud, a legal order), we tell you
[7] days before suspending, with the reason and what will end it. We reinstate your
cinema promptly once the reason is resolved. Suspensions and reinstatements are
recorded in our audit log and emailed to the owner.

## 13. How long this agreement lasts and how it ends

13.1 This agreement starts when you accept it and continues until either of us ends
it.

13.2 **You** may end it at any time by telling us through the back office or in
writing, with [30] days' notice.

13.3 **We** may end it:

- with [90] days' notice, for any reason;
- with [30] days' notice, if you haven't sold anything for [6] months;
- at once by notice, if you seriously break this agreement and don't fix it within
  [14] days of our notice, or can't fix it; if you're suspended for more than [60]
  days; or if you become insolvent, are wound up or stop trading.

13.4 Ending this agreement doesn't affect what either of us owes the other up to then.
Clauses 5 (for Fees already earned), 8.3, 9, 10, 11, 14 and 17 continue after it ends.

## 14. What happens to your data when this agreement ends

14.1 **Shows already sold.** Unless you've cancelled them, your Storefront stays able
to show and scan tickets for showtimes already sold, for up to [30] days after the
agreement ends, so Customers aren't stranded. You may instead cancel and refund them.

14.2 **Your copy.** For [60] days after the agreement ends, you can export your data
(your Customers, Orders, reports and Your Content) in a structured, machine-readable
format, free of charge.

14.3 **Deletion or return.** After that, we delete or return your Customers' Personal
Data, as you choose (General Regulations, reg 24(2)(e)), except what the law requires
us to keep. That includes order and payment records kept for five years for tax (Tax
Procedures Act, s.23) and for possible claims (Limitation of Actions Act), and the Fee
and invoice records. Kept data is restricted to those purposes and deleted when the
period ends.

14.4 Verification documents follow clause 7.4. Your Storefront's address stops working.
Your web address (slug) is held back for [12] months, so nobody can impersonate you,
and then released.

## 15. Notices

15.1 We send notices to the owner's email and in the back office. You send notices to
[legal@africinemas.co.ke] or through Help in the back office. A notice by email counts
as received the next working day after it's sent, unless the sender gets a message
that it wasn't delivered.

15.2 Each of us keeps its contact details current.

## 16. Changes to this agreement

16.1 We may publish a new version of this agreement. We tell you at least [30] days
before it takes effect ([60] days for a change to the Fee), and say what changes and
why.

16.2 The new version applies once you accept it in the back office. Until you accept
it, the previous version continues. If you don't accept it by the date it takes
effect, your cinema can't take new Orders (only existing tickets are honoured) until
you do, or until either of us ends the agreement under clause 13 [advocate: confirm
this mechanism is fair under Kenyan contract law].

16.3 Each version is published with its number and the date it applies from, and we
keep a record of which version you accepted, when, and who accepted it.

## 17. Law and disputes

17.1 This agreement is governed by the laws of Kenya.

17.2 **Talking first.** If a dispute arises, we each name someone senior to try to
settle it within [21] days of a written notice describing it.

17.3 **Mediation.** If that fails, either of us may refer the dispute to mediation
[under the Nairobi Centre for International Arbitration's mediation rules / by a
mediator agreed or, failing agreement, appointed by the Chartered Institute of
Arbitrators (Kenya Branch)].

17.4 **Arbitration or courts.** [Option A: disputes not settled by mediation within
[30] days are finally resolved by arbitration in Nairobi under the Arbitration Act,
1995, by one arbitrator. Option B: the courts of Kenya have exclusive jurisdiction.]
Either of us may still ask a court for urgent relief. [Advocate: recommend A or B;
this clause is between businesses, so s.88 of the Consumer Protection Act doesn't
apply.]

## 18. General

18.1 **The whole agreement.** This agreement, with its schedules and our privacy policy
and cookie notice as they apply to you, is the whole agreement between us about the
Platform.

18.2 **Order of precedence.** If they conflict: schedule 2 (data processing) first for
Personal Data, then these clauses, then the other schedules.

18.3 **Transfer.** You may not transfer this agreement without our written agreement.
We may transfer it to a company that takes over the Platform, if we tell you and the
new company takes on all our obligations.

18.4 **Subcontractors.** We may use subcontractors, and remain responsible for them.
Sub-processors of Personal Data follow schedule 2.

18.5 **If a clause is invalid**, the rest stays in force, and the invalid clause is
read as closely to its purpose as the law allows.

18.6 **Waiver.** Not enforcing a right at once doesn't waive it.

18.7 **No partnership.** Nothing in this agreement makes us partners, employer and
employee, or joint venturers. We're your agent only as clause 3.1 says.

18.8 **Third parties.** Only you and AfriCinemas can enforce this agreement.

18.9 **Language.** This agreement is in English. A translation is for convenience;
the English version prevails.

---

## Schedule 1: The Fee

| Item | Amount |
|---|---|
| The Fee | **10%** of the Order Total of every paid Order (tickets, snacks, 3D glasses and your booking fee), online or at the box office, by M-Pesa or cash |
| Set-up fee | None |
| Monthly subscription | None |
| M-Pesa charges | Safaricom's charges on your paybill or till are yours, under your contract with Safaricom |
| VAT | Added to the Fee when AfriCinemas is registered for VAT |
| Invoice | Monthly, on the 1st, for the previous month |
| Due | [14] days after the invoice date |
| How to pay | AfriCinemas' paybill [number], account: the invoice number |

Version [1], applying from [date]. The fee rule's history is kept in the platform
console (P15.1).

**Worked example.** A Customer buys two tickets at KES 600, a popcorn at KES 300 and a
KES 50 booking fee: the Order Total is KES 1,550, and the Fee is KES 155 (plus VAT when
registered). If you later refund the Customer, the Fee stays.

---

## Schedule 2: Data processing agreement

This schedule is the written contract required by section 42(2)(b) of the Data
Protection Act, 2019 and regulation 24 of the Data Protection (General) Regulations,
2021. The Cinema is the **controller**; AfriCinemas is the **processor**.

### 2.1 The processing (reg 24(2)(a))

| Particular | Detail |
|---|---|
| **Subject matter** | Providing the Platform for the Cinema's sales to Customers |
| **Duration** | While the agreement lasts, and until deletion or return under clause 14 |
| **Nature and purpose** | Hosting the Storefront; Customer accounts at the Cinema; taking bookings and holding seats; starting and confirming M-Pesa payments with the Cinema's keys; recording cash sales; sending tickets and booking emails; scanning tickets; snack pickup; reports; the booking assistant on the Storefront and the AI-app connector; if the Cinema turns on offers, showing Customers the box to ask for them and recording each Customer's consent and its withdrawal; support; security and fraud prevention for these |
| **Types of personal data** | Customers' names, email addresses, phone numbers (for M-Pesa), account passwords (stored hashed), bookings (showtimes, seats, snacks, glasses), payment records (amount, M-Pesa receipt number, phone, status), ticket and pickup codes, scan times, offers consent and its history, messages with the booking assistant, apps they connected and when, the Cinema's staff's names and actions on Customers' orders |
| **Categories of data subjects** | The Cinema's Customers and Storefront visitors who book; people named on bookings; the Cinema's staff, as far as their actions on Customers' orders are recorded |
| **Sensitive personal data** | None intended. The Cinema doesn't ask Customers for sensitive data through the Platform. Accessibility needs a Customer chooses to mention (for example, a wheelchair space) are used only to serve them |
| **The Cinema's rights and obligations** | As controller: deciding the purposes; its lawful basis for each; telling Customers through its own privacy policy (P14.3b); answering Customers' rights requests, with our help; notifying the Data Commissioner of breaches; its own registration with the Commissioner if required |

### 2.2 Instructions (reg 24(2)(b); s.42(2)(b))

AfriCinemas processes the Cinema's personal data **only on the Cinema's documented
instructions**. The instructions are this agreement, the Platform's settings the
Cinema chooses, and any further written instruction through the back office. If we
think an instruction breaks the Data Protection Act, we tell the Cinema and needn't
follow it. If the law requires us to process the data otherwise, we tell the Cinema
first unless the law forbids it.

We know that a processor who processes data other than as instructed is treated as a
controller for that processing (s.42(3)), and we don't.

### 2.3 Confidentiality (reg 24(2)(c); s.42(4))

Everyone at AfriCinemas or a sub-processor who can access the Cinema's personal data is
bound by a written duty of confidentiality, is trained in data protection, and has
access only as far as their work needs.

### 2.4 Security (reg 24(2)(d); s.41)

AfriCinemas keeps appropriate technical and organisational measures, and reviews them
at least every [12] months. They include:

- **Separation between cinemas**: every request is checked for the cinema it's for;
  an automated test covers every endpoint (the isolation registry);
- **access control**: staff roles with the least access they need, venue limits,
  shifts that end on sign-out, and an audit log of changes;
- **encryption** in transit (HTTPS) everywhere; the Cinema's M-Pesa keys encrypted at
  rest with a key kept outside the database; passwords hashed with scrypt;
- **private files**: verification documents and support images served only through
  signed-in endpoints, never by public address; uploads re-encoded;
- **minimisation**: only the data each feature needs; retention limits enforced by a
  scheduled job;
- **resilience**: backups, with restores tested [every quarter] (P16.8);
- **monitoring**: errors and suspicious activity watched, with an on-call rota (P16);
- **testing**: automated tests on every change, and a security review and outside
  penetration test before launch (P17.5).

Known limit, told openly: changing a password doesn't yet end other signed-in sessions
(JI-059); signing out everywhere is to be built before launch (P17.5).

### 2.5 Sub-processors (reg 25)

The Cinema authorises AfriCinemas to use the sub-processors listed below. AfriCinemas:

- has a written contract with each, with the particulars of reg 24(2);
- remains liable to the Cinema for each (reg 25(4));
- tells the Cinema at least [30] days before adding or replacing one, through the back
  office. The Cinema may object on reasonable data protection grounds; if we can't
  resolve the objection, the Cinema may end the agreement without penalty.

| Sub-processor | What for | Where | Transfer basis |
|---|---|---|---|
| [Hosting provider, chosen in P17.3] | Servers, database, file storage, backups | [Country] | [s.48 / reg 41 safeguards, or reg 42 (AU Convention country)] |
| [Email provider, chosen at go-live] | Sending tickets and booking emails | [Country] | [as above] |
| Anthropic, PBC | The booking assistant and AI designs (the model reads the conversation to answer it; no Customer data is used for AI designs) | United States | [s.48(c)(i) necessity for the service the Customer asks for, plus contractual safeguards under reg 41(1)(a); advocate to confirm] |

Safaricom isn't our sub-processor: it processes M-Pesa payments for the Cinema under
the Cinema's own contract with Safaricom.

### 2.6 Transfers outside Kenya (s.25(h), s.48, s.49; regs 40 to 42)

AfriCinemas transfers the Cinema's personal data outside Kenya only to the
sub-processors above, on the basis shown. It documents each kind of transfer (date,
recipient, justification, description of the data: reg 41(2)) and gives the
documentation to the Data Commissioner on request. We don't transfer sensitive
personal data outside Kenya.

### 2.7 Helping with Customers' rights (s.26 to s.40; regs 7 to 12)

The Platform lets the Cinema answer most requests itself (a Customer's bookings,
account and offers settings are in the back office). If a Customer asks AfriCinemas
directly about their data at the Cinema, we pass the request to the Cinema within
[2] working days and don't answer it ourselves unless the Cinema asks us to. We help
the Cinema meet the deadlines in the General Regulations (access within 7 days;
rectification, erasure, restriction and objection within 14 days; portability within
30 days). See [data-requests-procedure.md](data-requests-procedure.md).

### 2.8 Breaches (s.43(3))

If AfriCinemas becomes aware of a personal data breach affecting the Cinema's data, we
**tell the Cinema without delay and, where reasonably practicable, within 48 hours**,
with what s.43(5) and reg 38 require as far as we know it, and more in phases as we
learn it. We help the Cinema notify the Data Commissioner within 72 hours and tell the
people affected, and we record the breach. See [breach-procedure.md](breach-procedure.md).

### 2.9 Impact assessments and the Commissioner

We help the Cinema with any data protection impact assessment and any consultation with
the Data Commissioner about the Platform, and we cooperate with the Commissioner.

### 2.10 Deletion or return (reg 24(2)(e))

When the agreement ends, we delete or return the Cinema's personal data **as the
Cinema decides**, under clause 14, keeping only what the law requires, restricted to
that purpose.

### 2.11 Audits and inspections (reg 24(2)(f))

The Cinema may check our compliance with this schedule. We give it the information it
reasonably asks for within [14] days, and, once every [12] months (or after a breach
affecting it), allow an audit by the Cinema or an auditor it appoints who is bound by
confidentiality, on [30] days' notice, during working hours, without access to other
cinemas' data. The Cinema bears its own costs unless the audit finds we materially
broke this schedule. We may meet the request with an independent audit report instead,
if it covers what the Cinema needs.

---

## Schedule 3: Support and service levels

| Problem | Example | First response | Updates |
|---|---|---|---|
| **Critical** | Storefront or payments down for everyone; a data breach | [1 hour], any time | Every [2 hours] until fixed |
| **High** | A feature the Cinema needs for tonight's shows is broken | [4 hours] (08:00 to 23:00 EAT) | Every [8 hours] |
| **Normal** | Something works, but badly | [1 working day] | As progress is made |
| **Question** | How to do something | [2 working days] | — |

The Cinema reports problems through **Help** in the back office. Critical problems can
also be reported by phone on [number]. After every critical incident we share a short
write-up: what happened, why, and what we're changing (P16.8).

---

## Schedule 4: Acceptable use

The Cinema and its staff don't:

- break the law, including the Computer Misuse and Cybercrimes Act, 2018 and the Data
  Protection Act, 2019;
- try to reach another cinema's data, or test, probe or attack the Platform's security
  (report weaknesses to [security@africinemas.co.ke] instead);
- share sign-ins, or let anyone use the Platform who isn't on the Cinema's staff;
- sell shows they don't hold, or films without a KFCB certificate;
- upload content that's unlawful, infringes someone's rights, is hateful, or
  impersonates someone;
- send Customers marketing without their consent (Data Protection Act, s.37;
  General Regulations, reg 15), or collect Customers' data through the Platform for a
  purpose the Customer wasn't told about;
- use the Platform to collect payments for anything other than the Cinema's own shows,
  snacks and goods;
- overload the Platform on purpose, or copy it.
