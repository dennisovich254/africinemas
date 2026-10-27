# Builds core/legal/published/*.md (the public legal pages, P15.0b) from the drafts in
# docs/legal/: drops the draft notices, the notes to the advocate and internal
# references, and fills the bracketed choices. Run from the repo root after editing a
# draft, then read the result: python3 scripts/publish_legal.py

import re
SRC="docs/legal/"; DST="core/legal/published/"
def common(s):
    s=re.sub(r"\*\*Draft v0\.1, 2026-10-26\.[^\n]*(\n[^\n]+)*\n\n","",s,count=1)
    s=re.sub(r"\s*\[(?:Advocate|advocate|Decision|Decision for the owner)[^\]]*\]","",s,flags=re.S)
    ref=r"(?:P\d+(?:\.\d+)?[a-z]?(?:\.[a-z])?|ADR-\d+|JI-\d+|improvements #\d+)"
    s=re.sub(r"\s?\((?:"+ref+r")(?:(?:, | and |; |, and )"+ref+r")*\)","",s)
    s=re.sub(r"\s?\((?:owner's decision|decided|owner), 2026-10-2\d\)","",s)
    for a in ["help","privacy","legal","security"]:
        s=s.replace(f"[{a}@africinemas.co.ke]",f"{a}@africinemas.co.ke")
    s=s.replace("[status.africinemas.co.ke]","status.africinemas.co.ke")
    s=re.sub(r"\[(\d+(?:\.\d+)?)\]",r"\1",s)
    s=s.replace("Version [1], applying from [date].","")
    return s
def rep(s,pairs):
    for old,new in pairs:
        if old not in s: raise SystemExit(f"missing {old[:70]!r}")
        s=s.replace(old,new)
    return s
s=common(open(SRC+"cinema-agreement.md").read())
s=rep(s,[
("""- **[AfriCinemas Limited]**, a company registered in Kenya under the Companies Act, 2015
  with number [number], of [registered office], KRA PIN [PIN] (**"AfriCinemas"**,
  **"we"**); and""","""- **AfriCinemas** (**"we"**). AfriCinemas is being registered as a company in Kenya;
  its registered name, number, office and KRA PIN will be added here in a new version,
  which you'll be asked to accept; and"""),
("""- a booking assistant on your Storefront, and a connector so Customers may book
  through AI apps they choose to connect;""","""- a connector so Customers may book through AI apps they choose to connect;"""),
])
open(DST+"cinema-agreement.md","w").write(s)
for a,b in [("terms-of-use.md","terms.md"),("privacy-policy.md","privacy.md"),("cookies-and-storage.md","cookies.md")]:
    open(DST+b,"w").write(common(open(SRC+a).read()))

# ---- Second pass: decisions and the chat being off.
def fix(name, pairs):
    path=DST+name; s=open(path).read()
    s=s.replace("\n\nVersion 1, applying from [date].","")
    s=s.replace(" The fee rule's history is kept in the platform\nconsole.","")
    s=rep(s,pairs)
    open(path,"w").write(s)

fix("cinema-agreement.md",[
("the snack counter, the booking\n  assistant, reports and support.","the snack counter, reports and\n  support."),
("[18:00 to 23:00 East Africa Time]","18:00 to 23:00 East Africa Time"),
("to AfriCinemas' paybill\n[number] with the invoice number as the account number, or by bank transfer to\n[account]. Payments are matched","to AfriCinemas' paybill shown\non the invoice, with the invoice number as the account number. Payments are matched"),
("Our [DPIA](dpia-verification.md) explains\nwhy and how.","Our data protection impact\nassessment explains why and how."),
("Our [privacy policy](privacy-policy.md) covers it.","Our [privacy policy](/legal/privacy) covers it."),
("This clause lasts [five] years","This clause lasts five years"),
("""mediation
[under the Nairobi Centre for International Arbitration's mediation rules / by a
mediator agreed or, failing agreement, appointed by the Chartered Institute of
Arbitrators (Kenya Branch)].""","""mediation
by a mediator we agree or, failing agreement, one appointed by the Chartered Institute
of Arbitrators (Kenya Branch)."""),
("""17.4 **Arbitration or courts.** [Option A: disputes not settled by mediation within
30 days are finally resolved by arbitration in Nairobi under the Arbitration Act,
1995, by one arbitrator. Option B: the courts of Kenya have exclusive jurisdiction.]
Either of us may still ask a court for urgent relief.""","""17.4 **Courts.** Disputes not settled by mediation within 30 days go to the courts of
Kenya, which have exclusive jurisdiction. Either of us may still ask a court for
urgent relief at any time."""),
("the booking assistant on the Storefront and the AI-app connector;","the AI-app connector;"),
("offers consent and its history, messages with the booking assistant, apps they connected","offers consent and its history, apps they connected"),
("""| [Hosting provider, chosen in P17.3] | Servers, database, file storage, backups | [Country] | [s.48 / reg 41 safeguards, or reg 42 (AU Convention country)] |
| [Email provider, chosen at go-live] | Sending tickets and booking emails | [Country] | [as above] |
| Anthropic, PBC | The booking assistant and AI designs (the model reads the conversation to answer it; no Customer data is used for AI designs) | United States | [s.48(c)(i) necessity for the service the Customer asks for, plus contractual safeguards under reg 41(1)(a); advocate to confirm] |""",
"""| Our hosting provider | Servers, database, file storage, backups | Named here before we take real bookings | Appropriate safeguards (s.48; reg 41), or a country taken to have them (reg 42) |
| Our email provider | Sending tickets and booking emails | Named here before we take real bookings | As above |

Anthropic, which generates Storefront designs, receives only your brand details,
never Customers' personal data, so it isn't a sub-processor of it."""),
("30 days). See [data-requests-procedure.md](data-requests-procedure.md).","30 days)."),
("and we record the breach. See [breach-procedure.md](breach-procedure.md).","and we record the breach."),
("backups, with restores tested [every quarter];","backups, with restores tested every quarter;"),
("| [1 hour], any time | Every [2 hours] until fixed |","| 1 hour, any time | Every 2 hours until fixed |"),
("| [4 hours] (08:00 to 23:00 EAT) | Every [8 hours] |","| 4 hours (08:00 to 23:00 EAT) | Every 8 hours |"),
("| [1 working day] |","| 1 working day |"),
("| [2 working days] |","| 2 working days |"),
("Critical problems can\nalso be reported by phone on [number].","Critical problems can\nalso be reported by phone, on the number shown under Help."),
("| How to pay | AfriCinemas' paybill [number], account: the invoice number |","| How to pay | AfriCinemas' paybill shown on the invoice; account: the invoice number |"),
])
fix("terms.md",[
("**storefront**), its booking assistant, AfriCinemas through an AI app you connect, or","**storefront**), AfriCinemas through an AI app you connect, or"),
("1.1 AfriCinemas is run by **[AfriCinemas Limited]**, a company registered in Kenya with\nnumber [number], of [registered office]. Contact: help@africinemas.co.ke.",
 "1.1 AfriCinemas is being registered as a company in Kenya; its registered name, number\nand office will be added here. Contact: help@africinemas.co.ke."),
("""## 8. The booking assistant and AI apps

8.1 A storefront may have a **booking assistant**, an AI that helps you find shows and
book. It's run by AfriCinemas for the cinema, using a model from Anthropic.

8.2 **The assistant can make mistakes.** Check the showtime, seats and price on the
order before you pay. The order shown before Pay is what you're buying, not what the
assistant said.

8.3 The assistant never pays for you. You always confirm a payment yourself, on your
phone.

8.4 You can connect""","""## 8. AI apps

8.1 You can connect"""),
("""also apply to your use of it.

8.5 Don't share sensitive information (your health, ID numbers, PINs or passwords)
with the assistant.""","""also apply to your use of it.

8.2 **An AI app can make mistakes.** Check the showtime, seats and price on the order
before you pay. The order shown before Pay is what you're buying. An AI app never pays
for you: you always confirm a payment yourself, on your phone."""),
("see our [privacy policy](privacy-policy.md).","see our [privacy policy](/legal/privacy)."),
])
fix("privacy.md",[
("""**[AfriCinemas Limited]**, registered in Kenya with number [number], of [registered
office] (**"AfriCinemas"**, **"we"**). We're registered with the Office of the Data
Protection Commissioner as a data controller and a data processor, registration
number [number].

**Data protection contact:** [name or role], privacy@africinemas.co.ke, [postal
address], [phone].""","""**AfriCinemas** (**"we"**). AfriCinemas is being registered as a company in Kenya, and
we're registering with the Office of the Data Protection Commissioner as a data
controller and a data processor. Our company details and registration number will be
added here.

**Data protection contact:** privacy@africinemas.co.ke."""),
(", errors [and IP address: confirm at P16] |",", errors |"),
("See the [cookie and storage notice](cookies-and-storage.md)","See the [cookie and storage notice](/legal/cookies)"),
("""### 3.8 The booking assistant and AI designs

The booking assistant on a storefront is provided for the cinema (section 2): the
conversation is sent to our AI provider, Anthropic, to produce each answer. It's kept
in your browser for the visit only (see the cookie notice), and [on our servers for
30 days for safety and debugging: confirm]. AI designs for storefronts use the
cinema's brand details only, never customers' data.""","""### 3.8 AI designs

We use AI from Anthropic to design cinemas' storefronts. It's given the cinema's brand
details only (its name, logo and colours), never anyone's personal data."""),
("| [Hosting provider] | Servers, database, files and backups | [Country] |","| Our hosting provider | Servers, database, files and backups | Named here before we take real bookings |"),
("| [Email provider] | Sending emails | [Country] |","| Our email provider | Sending emails | Named here before we take real bookings |"),
("| Anthropic, PBC | Answering booking-assistant conversations; generating storefront designs | United States |","| Anthropic, PBC | Generating storefront designs from a cinema's brand details (no personal data) | United States |"),
("""contract, essentially equivalent to Kenyan law (s.48(a); reg 41), or, for the booking
assistant, that the transfer is necessary for the service you asked for (s.48(c)(i)).""","""contract, essentially equivalent to Kenyan law (s.48(a); reg 41), or a country taken
to have such safeguards (reg 42)."""),
("| [2 years after the request is closed] |","| 2 years after the request is closed |"),
("| While the account is in use; [12 months] after","| While the account is in use; 12 months after"),
("| Audit log | [6 years] |","| Audit log | 6 years |"),
("| [6 years]; at least 5 years |","| 6 years |"),
("| Technical request records | [90 days] |","| Technical request records | 90 days |"),
("(s.56): [odpc.go.ke], [complaints\ncontact to confirm].","(s.56), through its website, odpc.go.ke."),
])
fix("cookies.md",[
("regulation 6 of the General Regulations, 2021. See [law-register.md](law-register.md).","regulation 6 of the General Regulations, 2021."),
("| `africinemas:chat:<cinema>` | **Your conversation with the booking assistant**, so it's still there when you move between pages. It's gone when you close the tab | Storefronts | The service you asked for. Contract |\n",""),
("- **Close the tab** to remove the seat hold and the assistant conversation.","- **Close the tab** to remove the seat hold."),
])
c=open(DST+"cookies.md").read()
c=c.split("\n---\n\n**For the team")[0].rstrip()+"\n"
c=c.replace("# Cookies and storage\n\n","# Cookies and storage\n\nOne notice for every AfriCinemas site: `africinemas.co.ke`, the back office and every\ncinema's storefront. AfriCinemas writes the code that runs on all of them, so we, not\nthe cinemas, decide what's kept in your browser.\n\n",1)
open(DST+"cookies.md","w").write(c)
fix("privacy.md",[("our [impact assessment](dpia-verification.md)","our impact assessment")])
fix("cookies.md",[(" (decided 2026-10-24).",".")])
fix("cinema-agreement.md",[("We\npublish the Platform's status at status.africinemas.co.ke.","Before we\ntake real bookings, we'll publish the Platform's status at status.africinemas.co.ke.")])
fix("terms.md",[("Our status page is at\nstatus.africinemas.co.ke.","Our status page will be\nat status.africinemas.co.ke.")])
