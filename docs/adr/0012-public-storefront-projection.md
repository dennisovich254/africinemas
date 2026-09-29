# ADR-0012: A cinema's public storefront is a read-only projection on the shared guest graph

- **Status:** Accepted
- **Date:** 2026-09-29
- **Sub-phase:** P3.5b (spike S7)
- **Code:** `core/catalog/storefront.jac`, `core/catalog/screening_api.jac`, `core/tenancy/open_cinema.jac`
- **Tests:** `tests/spikes/s7_storefront_projection_tests.jac`, `tests/integration/publishing_tests.jac`, `tests/integration/publishing_concurrency_tests.jac`, `tests/isolation/`

## Context
Architecture §4: anonymous storefront visitors run on Jac's shared guest graph (`root.shared`), and published, non-sensitive data is projected there when it's published; the operational subgraph is never exposed. We hadn't yet written to the shared graph from staff code, so spike S7 checked it on a real server. (Outside a served process there are no separate users, and `root.shared` is just the caller's root.)

## What the spike showed
1. Acting as a cinema's principal (ADR-0003), staff code can hang a node off `root.shared`; the principal owns it, and after `grant(node, READ)` anonymous callers and other logged-in users can read it by id.
2. Anonymous callers can't change it or attach nodes under it.
3. Anyone can attach their own nodes to `root.shared` itself (its floor is CONNECT), so an impostor "Storefront" for any cinema can appear there.

## Decision
1. **One Storefront per cinema**, made on first publish, owned by the cinema's principal and granted READ. Its id is recorded on the Tenant (`storefront_id`). Public reads go slug → Tenant (read as the system root, `open_cinema`) → that id, and never search `root.shared`.
2. **Public fields only.** Anyone who has a node's id can read all of it. So `StorefrontScreening` nodes hold only what a visitor may see: movie details, venue name and city, screen name, times, state and the pinned layout's seat map. Tenant, venue, screen, movie and staff ids never go there. The isolation suite probes `public_screenings` anonymously at another cinema and checks that no tenant or owner ids leak.
3. **Publishing** (scheduled → published) creates the screening's seat inventory, one `SeatSlot` per seat of its pinned layout (BLOCKED and HOUSE seats not for sale), once, and writes its storefront entry. Unpublishing or cancelling removes the entry. Editing a movie refreshes the entries of its published screenings.
4. **Concurrency:** concurrent publishes all change the screening's state, so the database lets one through and re-runs the others (JI-031), which then find it published. There's one inventory and one entry, checked by a real-server race test.

## Consequences
- The storefront is a snapshot. Renaming a venue or screen doesn't refresh published entries yet; movie edits do. The storefront pages (plan 4.1) will add what they need, e.g. posters and prices (3.6).
- A cinema that closes keeps its Storefront node, but `open_cinema` stops answering for its slug.
