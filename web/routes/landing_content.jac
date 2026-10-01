"""The landing page's words (P3.9), kept apart from its layout (LandingPage.jac), so copy
changes never touch the page's structure.
"""

glob:pub HERO: dict[str, str] = {
         "title": "Sell your cinema's tickets online, paid with M-Pesa",
         "lead": "AfriCinemas gives your cinema its own booking website: your screenings, a seat map customers pick from on their phones, M-Pesa checkout and QR tickets your staff scan at the door.",
         "cta": "Create your cinema",
         "sign_in": "Sign in",
         "signed_in": "Your cinemas"
     },
     GLIMPSE: dict[str, str] = {
         "label": "What your customers see",
         "cinema": "Your cinema",
         "film": "Nairobi Half Life",
         "facts": "Drama · 1 h 36 min · 16",
         "pay": "Pay with M-Pesa",
         "total": "2 seats · KES 1,600"
     },
     STEPS: list[dict[str, str]] = [
         {
             "title": "Create your cinema",
             "text": "Sign up, name your cinema and choose its web address. Add your logo and colours whenever you like."
         },
         {
             "title": "Set up your screens and screenings",
             "text": "Draw each screen's seats, add your movies and prices, and publish the screenings you want to sell."
         },
         {
             "title": "Sell tickets with M-Pesa",
             "text": "Customers pick their seats on your website and pay from their phone. Your box office sells at the counter too."
         },
         {
             "title": "Scan QR tickets at the door",
             "text": "Every ticket carries a QR code. Ushers scan it with a phone, and each ticket works once."
         }
     ],
     FEATURES: list[dict[str, str]] = [
         {
             "title": "Seat maps you draw",
             "text": "Rows, aisles, VIP and wheelchair spaces, laid out the way your screen really is."
         },
         {
             "title": "Your brand, your storefront",
             "text": "Your logo, colours and fonts on your own booking page, readable in light and dark."
         },
         {
             "title": "Prices that fit your week",
             "text": "Adult and child tickets, seat zones, evening extras and matinee discounts, in shillings."
         },
         {
             "title": "Staff with the right access",
             "text": "Box office, ushers and managers each see what their role needs, at the venues they work at."
         },
         {
             "title": "Built for phones",
             "text": "Most customers book on a phone, so every page works on a small screen first."
         },
         {
             "title": "Several venues, one account",
             "text": "Run every location from one back-office, with screens and staff kept per venue."
         }
     ],
     AUDIENCE: list[dict[str, str]] = [
         {
             "title": "Independent cinemas",
             "text": "A single screen or two, run by a small team that wants online sales without an IT department."
         },
         {
             "title": "Multi-screen operators",
             "text": "Several screens or venues, with staff at each and prices that change by seat and time."
         },
         {
             "title": "Community and pop-up screenings",
             "text": "Film clubs and outdoor shows that need tickets, seat limits and a door check for a night."
         }
     ],
     CLOSING: dict[str, str] = {
         "title": "Open your online box office",
         "text": "Set it up at your own pace, then put your first screening on sale.",
         "cta": "Create your cinema"
     },
     FOOTER: str = "AfriCinemas · Cinema tickets, booked in seconds.";
