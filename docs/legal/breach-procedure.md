# Personal data breach procedure

**Draft v0.1, 2026-10-26. For review by a Kenyan advocate. Internal.** Section 43 of
the Data Protection Act, 2019, and regulations 37 and 38 of the Data Protection
(General) Regulations, 2021. P16.8's runbook for a data breach follows this procedure.
See [law-register.md](law-register.md).

## 1. What counts as a breach

A **personal data breach** is a breach of security leading to the accidental or
unlawful destruction, loss, alteration, unauthorised disclosure of, or access to,
personal data (s.2). Examples here:

- someone gets into an account that isn't theirs, or a cinema sees another's data;
- verification documents or support images are reachable without the right sign-in;
- a database, backup or export is lost, stolen or left public;
- an email of tickets goes to the wrong customers in bulk;
- a cinema's M-Pesa keys are exposed;
- data is deleted or altered by mistake and can't be restored.

## 2. Two roles, two clocks

| Whose data | Our role | Our deadline |
|---|---|---|
| A cinema's customers (bookings, accounts, payments, offers) | **Processor** | **Tell the cinema without delay, within 48 hours where reasonably practicable** (s.43(3)); the cinema notifies the Commissioner within 72 hours. We help |
| Cinema owners and staff accounts, verification, billing, support, our team | **Controller** | **Notify the Data Commissioner without delay, within 72 hours** of becoming aware (s.43(1)(a)), with reasons if later (s.43(2)); tell the people affected in writing within a reasonably practical period (s.43(1)(b)) |
| Both (most platform-wide incidents) | Both | Both clocks run |

**"Becoming aware"** is when anyone at AfriCinemas has a reasonable degree of certainty
that a breach happened. Start the clock then and write the time down; don't wait for
the investigation to finish.

## 3. Is it notifiable?

Notification is needed where personal data was **accessed or acquired by an
unauthorised person** and there's **a real risk of harm** (s.43(1)). Under reg 37,
there's taken to be a real risk of harm when the breach involves:

- a person's **name or identification number** together with any data in the Second
  Schedule, which includes card and bank account numbers, **deposits or withdrawals of
  money with any entity or payment system**, payments to the person, debts and
  creditworthiness. **M-Pesa payment records with customers' names or phone numbers
  are in this category**; or
- **an account identifier** (a username or email) together with **a password, security
  code, access code** or similar used to get into the account. **Our sign-in data and
  tokens are in this category.**

Data already public, or disclosed as the law requires, doesn't count (reg 37(3)).

**If in doubt, notify.** Telling the people affected isn't required where the data was
protected, for example by encryption, so that it's unintelligible (s.43(6)); we still
notify the Commissioner and record it.

## 4. The steps

| When | Who | What |
|---|---|---|
| **At once** | Whoever notices | Report it to the on-call person (P16.8) and in [#incidents]. Don't delete evidence |
| **Within 1 hour** | On-call | Open an incident record (the console's **Data protection → Breaches**, which starts the 48- and 72-hour clocks from the time we became aware); name an **incident lead** and the **data protection contact** |
| **Within 4 hours** | Incident lead | **Contain**: revoke access, rotate keys and passwords, take a public file offline, suspend an account or a cinema if needed. Keep logs |
| **Within 24 hours** | Data protection contact | **Assess**: what data, how many people, which cinemas, whether reg 37 makes it notifiable, our role (section 2) |
| **Within 48 hours** | Data protection contact | **Tell each affected cinema** (processor duty) with what's known (section 5), by email to the owner and in the back office. Offer a draft of their notice to the Commissioner and to customers |
| **Within 72 hours** | Data protection contact | **Notify the Data Commissioner** for our controller data (section 5). If details are missing, notify with what's known, and send the rest in phases without undue delay (s.43(7)) |
| **As soon as practical** | Data protection contact | **Tell the people affected** in writing (for our controller data), unless s.43(4) or s.43(6) applies; help cinemas tell their customers |
| **Within 2 weeks** | Incident lead | Fix the cause; write the incident report (P16.8) and share a summary with the cinemas affected |
| **Always** | Data protection contact | **Record** every breach, notifiable or not: the facts, its effects and the remedial action (s.43(8)) |

## 5. What the notices contain

**To the Data Commissioner** (reg 38(1)):

1. the date and circumstances in which we became aware;
2. a chronology of the steps taken since, including how we decided it's notifiable;
3. how the breach happened, where known;
4. how many people are affected;
5. the personal data or classes of data affected;
6. the potential harm to them;
7. what we've done or will do to eliminate or reduce the harm, and to fix what caused
   it;
8. what we've told the people affected or the public, and how they can protect
   themselves;
9. a contact person;
10. if we won't tell the people affected, why (reg 38(2)).

**To the people affected** (s.43(5)): in plain words,

1. what happened;
2. what we've done and will do;
3. what they should do (for example: change your password; watch for M-Pesa messages
   you don't expect; never share your PIN);
4. who accessed the data, where known;
5. who to contact for more.

**To a cinema** (processor duty): the same facts, which customers and data are
affected, and what we need from the cinema.

Templates for each are in [P16.8's runbook].

## 6. Delaying the notice to people

We may delay or limit telling the people affected only as far as needed and
proportionate to prevent, detect or investigate an offence, on the request of the
relevant body (s.43(4)). Record the request.

## 7. Other reports

- **The police / the National Computer and Cybercrimes Coordination Committee**, where
  the breach is an offence under the Computer Misuse and Cybercrimes Act, 2018
  [advocate: confirm any reporting duty].
- **Safaricom**, where M-Pesa keys or paybills are involved.
- **Our insurer**, if we hold cyber cover.

## 8. After every breach

Review this procedure, the DPIA and the risks. Tell the cinemas affected what's
changing (P16.8).
