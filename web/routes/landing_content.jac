"""The landing page's words (P3.9), kept apart from its layout (LandingPage.jac), so copy
changes never touch the page's structure. The example cinema and films in the step
illustrations are invented.
"""

glob:pub HERO: dict[str, str] = {
         "eyebrow": "For cinemas in Kenya",
         "title": "Your cinema's box office, online",
         "lead": "A booking website for your cinema. Customers choose their seats on a phone, pay with M-Pesa and show a QR ticket at the door.",
         "cta": "Create your cinema",
         "more": "See how it works",
         "sign_in": "Sign in",
         "signed_in": "Your cinemas",
         "video": "/static/assets/landing/hero-cinema",
         "pause": "Pause background video",
         "play": "Play background video"
     },
     STEPS_HEAD: dict[str, str] = {
         "title": "Open for bookings in three steps",
         "text": "Set up once in the back-office. After that, your customers do the rest from their phones."
     },
     STEPS: list[dict[str, str]] = [
         {
             "title": "Set up your screens and screenings",
             "text": "Draw each screen's seats, add your films and prices in shillings, and publish the screenings you want to sell.",
             "proof": "programme"
         },
         {
             "title": "Sell tickets with M-Pesa",
             "text": "Customers pick seats on your booking page and confirm the payment on their phone. Seats are held while they pay, and your box office sells from the same seat map.",
             "proof": "mpesa"
         },
         {
             "title": "Scan tickets at the door",
             "text": "Every ticket carries a QR code, sent by email. Ushers scan it with a phone, and each ticket gets in once.",
             "proof": "ticket"
         }
     ],
     # The step illustrations: an example screen's programme, the M-Pesa prompt and a ticket.
     PROGRAMME: list[dict[str, str]] = [
         {"title": "Nairobi Nights", "time": "18:15", "state": "On sale"},
         {"title": "The Long Rains", "time": "15:00", "state": "On sale"},
         {"title": "Matatu Run", "time": "21:00", "state": "Not published"}
     ],
     MPESA: dict[str, str] = {
         "caption": "Checkout · 2 seats · F7, F8",
         "prompt": "Do you want to pay KES 1,600 to NOVA CINEMAS?",
         "pin": "Enter M-PESA PIN"
     },
     TICKET: dict[str, str] = {
         "film": "Nairobi Nights",
         "when": "Fri 3 Oct · 18:15",
         "where": "Screen 1 · Seats F7, F8"
     },
     CLOSING: dict[str, str] = {
         "title": "Open your online box office",
         "text": "Set it up at your own pace, then put your first screening on sale.",
         "cta": "Create your cinema"
     },
     AUDIENCE: list[tuple[str, str]] = [
         ("Independent cinemas", "one or two screens"),
         ("Multi-venue operators", "staff per venue"),
         ("Film clubs", "one-night screenings")
     ],
     FOOTER: str = "AfriCinemas · Cinema tickets, booked in seconds.";
