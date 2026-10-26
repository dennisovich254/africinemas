# Questions for the advocate

**Draft v0.1, 2026-10-26.** Everything we couldn't settle by reading the law, in order
of how much it matters to going live. Each refers to the document and clause it
affects. The laws are in [law-register.md](law-register.md).

## Could stop or delay the launch

1. **Payment services.** Today, while we're building, every cinema's M-Pesa payments go
   into one AfriCinemas paybill. From P15.3, each cinema's payments go straight to its
   own paybill and AfriCinemas never holds customers' money: we start the payment
   request with the cinema's own Daraja keys, and receive the confirmation. Given the
   National Payment System Act, 2011 and the High Court's wide reading of "payment
   service provider" in *KENEX v CBK* [2022] KEHC 13189, **does AfriCinemas need the
   Central Bank's authorisation, in either model?** May we pilot before P15.3, with our
   own paybill, at all? (Cinema agreement 3.2, 4.)
2. **DPIA submission.** Section 31(5) of the Data Protection Act says DPIA reports
   "shall be submitted sixty days prior to the processing". **Must we submit the
   verification DPIA to the ODPC 60 days before the first real cinema is verified?**
   Does it apply to other processing (bookings at scale, the AI assistant)? This could
   set the pilot's earliest date. ([DPIA](dpia-verification.md) Part 4.)
3. **ODPC registration.** We read the Registration Regulations as requiring us to
   register as both **controller and processor**, regardless of size, because we
   process data for direct marketing (cinemas' offers emails). Do you agree? Must each
   **cinema** register too (hospitality? direct marketing?), and should the agreement
   make that their duty? ([Checklist](registrations-checklist.md) 5, 6; agreement 6.1.)
4. **Amendments.** We read the Data Protection Act as gazetted in 2019, the General
   Regulations as gazetted in 2021, the Consumer Protection Act as revised to 31
   December 2022, and the Films and Stage Plays Act as revised in 2012. **Have any been
   amended in ways that change these documents?** (For example, the Films and Stage
   Plays Act and KFCB's 2024 regulations.)

## The cinema agreement

5. **Agent, not seller.** Is clause 3.1 (the cinema sells; AfriCinemas takes bookings
   and starts payments as the cinema's agent) effective under Kenyan law, including for
   the Consumer Protection Act's "supplier" and for VAT on tickets?
6. **Liability cap.** Is a cap at 12 months' fees (11.3) enforceable and reasonable?
   Should data protection liability (s.65) be capped, uncapped, or have its own cap?
7. **Changing the agreement.** Is clause 16.2 fair: a new version applies once
   accepted, and a cinema that doesn't accept can't take new orders until it does or
   either side ends the agreement?
8. **Disputes.** Arbitration (Arbitration Act, 1995) or the courts, between AfriCinemas
   and cinemas (17.4)? Which mediation body?
9. **The fee on refunds.** Is keeping the fee on refunded orders (5.3) sound, and
   should cancellations by the cinema or Platform failures be treated differently?
10. **Late payment.** Can we charge interest on late invoices, and at what rate (5.8)?
11. **Suspension.** Is a 30-day period after the due date, with 7 days' notice, enough
    (12.1, 12.3)? What do we owe customers holding tickets for a suspended cinema?
12. **KFCB licence.** Should verification also collect the cinema's KFCB exhibitor
    registration and annual licence (Films and Stage Plays Act, s.12; the 2024
    Distribution and Exhibition Regulations)? (Agreement 6.1, 7.1.)
13. **Withholding tax** on our fee: does it apply (5.7)?

## Customers

14. **Consumer Protection Act, s.31 and s.32.** Is our booking flow enough: the order
    shown in full before **Pay**, the terms linked beside the button, "pressing Pay is
    accepting", and the confirmation email as the written copy with the terms' version
    linked? Is anything "prescribed" (regulations under the Act) that we must also
    disclose? ([Terms](terms-of-use.md) 4.)
15. **Accepting terms at sign-up.** Is "creating an account is agreeing" enough, or do
    we need a tick box?
16. **Age.** Accounts and payments are for 18 and over (Data Protection Act, s.33).
    Is a declaration enough as the "age verification mechanism" s.33(2) asks for,
    given we collect nothing about children?
17. **The cinema's terms vs ours.** Is clause 1.3 of the terms of use (the cinema's
    terms prevail for the booking) workable?
18. **Liability to customers.** Is clause 10.3 of the terms of use enough, given s.5(3)
    of the Consumer Protection Act voids terms that vary implied warranties?

## Data protection

19. **Lawful basis for verification.** We rely on legitimate interests (s.30(1)(b)(vii))
    rather than consent, because verification is a condition of going live (s.32(4)).
    Do you agree? ([DPIA](dpia-verification.md) Part 2.)
20. **Verification files abroad.** If they're stored outside Kenya, and an ID document
    could be "sensitive personal data" (property or family details, s.2), do we need
    the owner's consent under s.49(1)? We'd prefer to store them in Kenya, or in a
    country that's ratified the AU Convention (reg 42). Which countries qualify?
21. **The AI assistant abroad.** Customers' conversations go to Anthropic in the United
    States. Is s.48(c)(i) (necessary for the service the customer asks for) a sound
    basis, with contractual safeguards under reg 41? What documentation does reg 41(2)
    need for a continuous flow (not single transfers)?
22. **A data protection officer.** Is one required (s.24(1)(b): regular and systematic
    monitoring?), or is a named contact enough?
23. **Deadlines.** Are the regulations' days calendar days? Does the clock pause while
    we check a requester's identity?
24. **Retention.** Are the periods in the [privacy policy](privacy-policy.md#7-how-long-we-keep-it)
    right, particularly 6 years for the audit log and billing, and 90 days for ID
    photos?
25. **Breaches.** Is there a duty to report cyber incidents to anyone other than the
    ODPC (Computer Misuse and Cybercrimes Act, 2018)?
    ([Breach procedure](breach-procedure.md) 7.)

## Films and content

26. **Posters online.** Is a storefront a "public place" for s.13 of the Films and
    Stage Plays Act (posters need the Board's approval)? Does AfriCinemas, as the host,
    have any duty?
27. **Ratings in listings.** We read s.17(3) as requiring the KFCB rating in "all
    advertisements", so every storefront listing shows it. Is that right, and is the
    rating enough without the full ruling's words ("for adults only", "unsuitable for
    children under 16")?
28. **AI designs.** Who owns an AI-generated storefront design under the Copyright Act,
    2001, and is clause 8.4 of the agreement sound?

## Tax

29. **The VAT (Digital Marketplace Supply) Regulations, 2023.** Do any parts apply to a
    resident platform like AfriCinemas (registration without the threshold)?
30. **Significant Economic Presence Tax** and similar: anything that applies to us as a
    resident company? (We assume not.)
31. **eTIMS**: confirm that our fee invoices must go through eTIMS from the first one.
