# Runbook: a real M-Pesa sandbox payment (plan 5.7)

The goal of 5.7: **a real Safaricom sandbox STK payment produces a ticket.** This runbook sets that up on a development laptop. Part 1 is a quick automated check; part 2 is the full journey in the browser with your own phone.

You need:
- a Safaricom developer account;
- a Safaricom phone number you can receive the prompt on;
- about 30 minutes the first time.

Everything secret goes in `.env`, which is never committed (only `.env.example` is, with empty values).

## 1. Daraja sandbox credentials

1. Sign in at <https://developer.safaricom.co.ke> and create an app (**My Apps → Add a new app**) with the **M-Pesa Express (Lipa Na M-Pesa Online) Sandbox** product. The app page shows its **Consumer Key** and **Consumer Secret**.
2. The sandbox test credentials (**APIs → M-Pesa Express → Simulate**, or the test credentials page) give the **Business Short Code**, usually `174379`, and its **Passkey**.
3. Add them to `.env`:

```bash
DARAJA_CONSUMER_KEY=<consumer key>
DARAJA_CONSUMER_SECRET=<consumer secret>
DARAJA_SHORTCODE=174379
DARAJA_PASSKEY=<passkey>
DARAJA_TEST_PHONE=07XX XXX XXX        # your phone, for the quick check
DARAJA_CALLBACK_BASE=https://example.invalid   # replaced in step 3
```

## 2. Quick check: login, a push, a status query

```bash
cd ~/africinemas && scripts/sandbox.sh 2>&1 | tee ~/out.txt
```

- **What it does:** logs in to the sandbox, sends a **KES 1** STK push to `DARAJA_TEST_PHONE`, waits 5 seconds, then asks Safaricom for the push's status. Your phone shows the M-Pesa prompt; cancelling it is fine for this check.
- **What passes:** Safaricom accepts the push (a `ws_CO_…` checkout id), and the status is one the adapter understands: still processing, paid, failed or cancelled.
- **If a setting is missing,** it says which one and passes without calling Safaricom.

To replace the contract-test fixtures (written from Safaricom's documentation in 5.2) with Safaricom's real replies:

```bash
DARAJA_RECORD=1 scripts/sandbox.sh
```

This writes the replies to `tests/fixtures/daraja/recorded/`, with tokens, passwords and phone numbers replaced by `REDACTED`. Read them before committing; the commit hook's secret scan runs too.

## 3. A public address for Safaricom's callback

Safaricom sends the result to `DARAJA_CALLBACK_BASE/hooks/mpesa/<token>`, which must be a public **https** address. A free Cloudflare quick tunnel gives your laptop one:

```bash
# once: install cloudflared (Ubuntu)
curl -L -o /tmp/cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i /tmp/cloudflared.deb

# each session: a tunnel to the dev server (keep this terminal open)
cloudflared tunnel --url http://localhost:8000
```

It prints a URL like `https://random-words.trycloudflare.com`. Put it in `.env` as `DARAJA_CALLBACK_BASE`. The address changes every time the tunnel starts, so update `.env` each session.

## 4. Start the server with real M-Pesa

In a second terminal:

```bash
cd ~/africinemas
set -a; source .env; set +a
AFRICINEMAS_PAYMENTS=daraja jac run --dev main.jac 2>&1 | tee ~/out.txt
```

Check it's reachable through the tunnel: opening `https://<tunnel>/healthz` in a browser should answer.

## 5. A cinema that charges KES 1

Sandbox payments should be tiny. In the back office (`http://localhost:8000`):
1. Use or create a test cinema with a venue, a screen with a published seat layout, and a movie.
2. **Settings → Prices:** one ticket type (Adult) at **KES 1**, booking fee **KES 0**, no extras.
3. **Screenings:** add a showtime later today or tomorrow and **publish** it.

## 6. Book and pay with your phone

1. Open the cinema's storefront (`http://localhost:8000/c/<slug>`) and pick the showtime.
2. Choose **one seat**, **Continue**, keep **Adult**, then **Proceed to pay**.
3. Enter your M-Pesa number and press **Pay KES 1 with M-Pesa**.
4. Your phone shows the M-Pesa prompt. Enter your PIN.
5. Within a few seconds the page shows **You're booked** with your ticket and its reference. ✓ That's plan 5.7's check.

In the server log you should see Safaricom's callback arrive (`POST /hooks/mpesa/…`). If it doesn't (tunnel down, wrong `DARAJA_CALLBACK_BASE`), the payment still settles: the resolver asks Safaricom directly within about a minute.

Also worth trying:
- **cancel** the prompt on your phone: the page says the payment was cancelled and offers **Try again**;
- **ignore** it: after Safaricom gives up, the payment fails or times out and you can try again until the order's time runs out.

## 7. Nightly check on GitHub (optional)

Add the same values as repository secrets (**Settings → Secrets and variables → Actions**):

| Secret | Value |
| --- | --- |
| `DARAJA_CONSUMER_KEY` | consumer key |
| `DARAJA_CONSUMER_SECRET` | consumer secret |
| `DARAJA_SHORTCODE` | `174379` |
| `DARAJA_PASSKEY` | passkey |
| `DARAJA_CALLBACK_BASE` | any https URL (the nightly check sends no callbacks it waits for) |
| `DARAJA_TEST_PHONE` | a number for the nightly prompt |

The **Daraja sandbox** workflow then runs the quick check every night at 04:30 Nairobi time, or on demand (**Actions → Daraja sandbox → Run workflow**). It isn't a required check, because it depends on Safaricom being up. Without the secrets it skips itself.

## Troubleshooting

| What you see | Likely cause |
| --- | --- |
| `Daraja refused the credentials` | Wrong consumer key or secret. |
| Login ok, then `404.001.03 Invalid Access Token` on the push | The Daraja app doesn't include the **M-Pesa Express** sandbox product: add it, or create an app with it, and use that app's key and secret. |
| `invalid_request: … https callback URL` | `DARAJA_CALLBACK_BASE` isn't an `https://` address. |
| `Bad Request - Invalid PhoneNumber` | The number isn't a Safaricom 07…/01… number. |
| `500.001.1001 Unable to lock subscriber` | A prompt is already open on that phone; wait a minute and try again. |
| Paid on the phone but the page keeps waiting | The callback can't reach you (tunnel or URL); the resolver settles it within about a minute. |
| `Set AFRICINEMAS_PAYMENTS…` on the pay button | The server was started without `AFRICINEMAS_PAYMENTS=daraja`. |
