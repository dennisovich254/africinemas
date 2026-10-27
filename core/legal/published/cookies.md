# Cookies and storage

One notice for every AfriCinemas site: `africinemas.co.ke`, the back office and every
cinema's storefront. AfriCinemas writes the code that runs on all of them, so we, not
the cinemas, decide what's kept in your browser.

Kenya has no law just for cookies. What your browser keeps is covered by the Data
Protection Act, 2019 where it relates to you (for example, a sign-in token that says
which account is yours), including the information "associated with web browsing" in
regulation 6 of the General Regulations, 2021.

## In short

- **We set no cookies.**
- **No tracking, analytics or advertising.** Nothing follows you across sites, and
  nothing is shared with advertisers. If we ever want analytics, we'll ask first,
  with a banner, and set nothing until you agree.
- What we do keep in your browser is only what the site needs to work, listed below.
- **Videos:** a trailer from YouTube or Vimeo loads only when you press Play. Then
  YouTube or Vimeo may set their own cookies.

## What we keep in your browser

Browsers have two kinds of storage we use. **Local storage** stays until you sign out
or clear it. **Session storage** lasts only while the tab is open. Each website address
has its own: a cinema's storefront can't read another's, or the back office's.

### Local storage (until you sign out or clear it)

| Name | What it's for | Where | Why it's needed |
|---|---|---|---|
| `africinemas_token:customer:<cinema>`, `africinemas_token:staff` (and `jac_token` while a page is loading) | Your **sign-in**: the token that shows the server you're signed in. A customer's is kept separately per cinema, and staff's separately again, so signing in at one doesn't sign you in at another. Deleted when you sign out; it expires after 7 days | Storefronts, back office, console | Without it you'd sign in on every page. Lawful basis: the contract you asked for (s.30(1)(b)(i)) |
| `africinemas_email` | The **email you signed in with** to the back office, offered back to the server when you create a cinema or accept an invitation. The server keeps it only after checking it's yours | Back office | Convenience and checking that an invitation reaches the right account: legitimate interests |
| `africinemas:venue:<cinema>` | The **venue you chose** at a cinema with several, so you don't choose again | Storefronts | Convenience: legitimate interests. Doesn't identify you |
| `africinemas:setup-guide-hidden:<cinema>` | Whether you **hid the setup guide** in the back office | Back office | Convenience. Doesn't identify you |

### Session storage (only while the tab is open)

| Name | What it's for | Where | Why it's needed |
|---|---|---|---|
| `africinemas:holder` | A random code for **the seats held for you** while you book, so the same tab keeps its hold and nobody else's | Storefronts | Booking can't work without it. Contract |
| `africinemas_site` | Which **kind of AfriCinemas site** the address is (a storefront, the back office, the console) | Everywhere | The site can't show the right pages without it. Doesn't identify you |
| `africinemas_preview` | A cinema team's short-lived **preview pass**, to see its storefront before it goes live | Storefronts (cinema staff only) | Lets a cinema check its site privately. Expires on its own |

## Videos from YouTube and Vimeo

Cinemas can add trailers. We embed them from **YouTube's privacy-enhanced mode**
(`youtube-nocookie.com`) or **Vimeo with "do not track"**, and only once you press
**Play**: until then, nothing is loaded from them. When you press Play, the player
says it's from YouTube or Vimeo and that it may set its own cookies. Their privacy
policies apply:

- YouTube (Google): https://policies.google.com/privacy
- Vimeo: https://vimeo.com/privacy

## What AI apps keep

If you connect an AI app (such as Claude) to book for you, that app keeps its own
records under its own privacy policy. Nothing about it is kept in your browser by
AfriCinemas.

## Your choices

- **Sign out** to remove your sign-in token.
- **Close the tab** to remove the seat hold.
- **Clear this site's data** in your browser's settings to remove everything above.
  You'll need to sign in again and choose your venue again.
- **Don't press Play** on a trailer if you don't want YouTube or Vimeo to load.

## Changes

If we add anything to your browser's storage, we update this notice first. Anything
that isn't needed for the site to work (analytics, for example) will wait for your
consent through a banner.
