# Manually testing P12.14: more snacks later

Use a test cinema with a future showtime, an available snack product and a test
payment provider. The box office account needs an open shift and permission to
sell at that venue.

1. Buy a ticket with one snack. Save the booking reference, ticket QR and snack
   pickup code.
2. Open the private tickets link. Select **Add snacks**, choose another item and
   continue to payment. The total should include only the new items.
3. Enter an email and M-Pesa number and complete the simulated payment. Expect
   **Extra snacks added**. Reload the tickets page: the ticket is unchanged, the
   snacks include both purchases, and the pickup code is unchanged.
4. While signed in as the customer, open **My tickets**. Select **Add snacks** on
   that booking and repeat. An unpaid addition must not appear as purchased.
5. In **Box office → Existing booking**, enter the booking reference. Add a snack,
   choose **Cash received**, and confirm. Expect the same pickup code. Repeat
   with M-Pesa if needed.
6. In **Snack counter**, look up the pickup code. Check the items and hand them
   over. Looking up the code again should show that they were collected.
7. Before the show starts, add another snack to the same booking. At the snack
   counter, only the new batch is ready; earlier items appear under **Already
   collected**. Hand over the new batch, then try again: a second handover is refused.
8. Leave an addition unpaid until its payment deadline. After the resolver runs,
   stock availability should recover. The original tickets remain valid.
9. After showtime starts, the tickets page must no longer offer additions. An
   already-open picker must be refused by the server when placing or paying.
10. Check Reports: the new payments increase snack takings only; ticket counts and
    ticket takings stay unchanged.

Repeat the picker and payment steps at phone width and in dark mode. CI screenshots
are stored with the browser test artifacts under `more-snacks-*`.
