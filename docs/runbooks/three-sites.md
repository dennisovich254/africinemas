# Runbook: AfriCinemas' three sites (plan 13.1b)

AfriCinemas is three websites served by one app (ADR-0057). The address a visitor uses decides which site they get.

| Site | Production | Development |
|---|---|---|
| Back office (cinemas' owners and staff) | `africinemas.co.ke` | `localhost:8000` |
| Platform (AfriCinemas staff) | `admin.africinemas.co.ke` | `admin.localhost:8000` |
| A cinema's storefront | `<slug>.africinemas.co.ke` | `<slug>.localhost:8000` |

Each site has its own accounts (ADR-0037, ADR-0056). Browsers keep each address's storage apart, so a sign-in on one never reaches another.

## Production

### 1. Settings

In the server's environment (the non-secret ones are in `deploy/production.env`):

```bash
AFRICINEMAS_SITE_DOMAIN=africinemas.co.ke
AFRICINEMAS_PUBLIC_URL=https://africinemas.co.ke     # ticket emails, Claude's links, M-Pesa callbacks
AFRICINEMAS_PLATFORM_ADMINS=<your email>             # the platform's super admins
```

`AFRICINEMAS_PUBLIC_URL` must be on the domain. Then ticket emails and Claude's answers link to each cinema's own address.

### 2. DNS

At the DNS provider, point two names at the server:

| Type | Name | Value |
|---|---|---|
| A (and AAAA, if the server has IPv6) | `africinemas.co.ke` | the server's address |
| A (and AAAA) | `*.africinemas.co.ke` | the server's address |

The wildcard covers `admin.`, `www.` and every cinema, including cinemas that sign up later, so nothing changes in DNS when a cinema joins.

### 3. Certificate and proxy

The addresses need one wildcard certificate for `africinemas.co.ke` and `*.africinemas.co.ke`. Let's Encrypt only issues wildcards through its DNS challenge, so the proxy needs an API token from the DNS provider that may edit the zone.

`deploy/Caddyfile` does this with Caddy and Cloudflare:

1. Build Caddy with the Cloudflare plugin: `xcaddy build --with github.com/caddy-dns/cloudflare`.
2. Create a Cloudflare API token with **Zone → DNS → Edit** on `africinemas.co.ke` only.
3. Give it to Caddy as `CLOUDFLARE_API_TOKEN` in its environment (a systemd drop-in, say). It never goes in the Caddyfile or the repository.
4. Start Caddy with `deploy/Caddyfile`. It gets the certificate and renews it on its own.

Any other proxy works too, as long as it:
- terminates HTTPS for the domain and the wildcard;
- passes the request's `Host` header through unchanged, because the app reads it to choose the site;
- sends everything to the app's port.

### 4. Check

```bash
scripts/check_sites.sh africinemas.co.ke <a cinema's slug>
```

Each address is asked, over its own URL, which site it is. That checks DNS, the certificate and the `Host` header in one go. Every line should start with `ok`. The last line checks that an address belonging to no cinema shows no site.

### 5. The first super admin

On the server, from the repository:

```bash
scripts/platform_setup.sh
```

It prints a link for each email in `AFRICINEMAS_PLATFORM_ADMINS`, valid for 24 hours and usable once. Open it, choose a password, and you're in the console at `admin.africinemas.co.ke`. Invite everyone else from **Platform staff**. Run the script again whenever a super admin forgets their password.

## Development

Put these in `.env`:

```bash
AFRICINEMAS_SITE_DOMAIN=localhost:8000
```

Then open `localhost:8000` (back office), `admin.localhost:8000` (platform) and `<slug>.localhost:8000` (a storefront). Browsers send every `*.localhost` address to this machine, and the dev server accepts them, so there's nothing else to set up.

### Behind a tunnel (testing on a phone, M-Pesa callbacks)

A quick tunnel (`cloudflared tunnel --url ...`) serves one address only, with no `admin.` or cinema names under it. So any address outside `AFRICINEMAS_SITE_DOMAIN` serves the back office and every storefront the old way, under `/c/<slug>`. With:

```bash
AFRICINEMAS_PUBLIC_URL=https://<tunnel>.trycloudflare.com
AFRICINEMAS_SITE_DOMAIN=localhost:8000
```

the phone opens `https://<tunnel>.trycloudflare.com/c/<slug>`, and ticket emails link there. The platform is only on `admin.localhost:8000`, on this machine.

## Troubleshooting

| What you see | Why | Fix |
|---|---|---|
| Every address shows the back office, storefronts are under `/c/<slug>` | The address isn't under `AFRICINEMAS_SITE_DOMAIN`, or the proxy changed the `Host` header | Check the setting. Make the proxy pass `Host` through. |
| A cinema's address says "Page not found" | No open cinema has that slug | Check the slug in the back office. A cinema that's closing has no storefront. |
| The platform's join link goes nowhere | The link was printed under an old `AFRICINEMAS_SITE_DOMAIN` | Fix the setting and run `scripts/platform_setup.sh` again (a new link replaces the old one). |
| The browser warns about the certificate on a cinema's address | The certificate doesn't cover the wildcard | Make sure the proxy asked for `*.africinemas.co.ke` (DNS challenge). |
