"""Reconciliation (P15.6, ADR-0085): our records checked against M-Pesa's and the cash.

Owner's decisions: no extra Daraja credentials (2026-10-28), and no M-Pesa statement
uploads (2026-10-29). Two checks, each turning what doesn't add up into an
**exception** for the cinema and the console:

1. **Every day, M-Pesa is asked again** about each payment of the last LOOKBACK_DAYS, with
   the account it was made with (provider_of), once per payment it answers about (one
   it doesn't know, or hasn't answered yet, is asked again next time):
   - `not_paid`: we sold on it, but M-Pesa says it wasn't paid;
   - `no_order`: M-Pesa says it was paid, but nothing was sold for it;
   - `amount_differs`: M-Pesa's amount isn't ours.
   And every receipt is on one payment only (`receipt_twice`).
2. **A cash-up** at the box office: the cash counted against the cash sales (less cash
   refunds) recorded by that member of staff since their last cash-up. Any
   difference is `cash_short` or `cash_over`. The count may be corrected once within
   RECOUNT_SECONDS, both figures kept (P15.6b). Staff can't sign out with cash
   uncounted; cash left by someone who didn't sign out is `cash_not_counted` once
   their shift is over, and the next at that venue counts it on their behalf
   (left_behind) before selling for cash.

Each exception is kept once (a claim on its kind and what it's about), so checks that
run again add nothing. Staff who read the reports mark one resolved with a note; it
stays listed, resolved.
"""

import os;
import from datetime { datetime, timedelta }
import from core.clock { now }
import from core.claims { claim, release }
import from core.catalog.answers { Refused }
import from core.tenancy.models { Tenant }
import from core.tenancy.groups { attach_to_tenant }
import from core.tenancy.principal {
    node_id,
    act_as,
    restore,
    flush_now,
    fresh_node_id
}
import from core.catalog.models { Venue, Auditorium, Screening }
import from core.booking.models { Order }
import from core.payments.models { PaymentIntent }
import from core.payments.ledger { LedgerEntry }
import from core.payments.state { PaymentState }
import from core.payments.payment_api { provider_of }
import from core.authz.policy { ROLE_PERMISSIONS }
import from core.tenancy.membership { records_of }
import from core.tenancy.shifts { shift_is_open, shift_started_at }

glob LOOKBACK_DAYS: int = 3,
     CHECKED: str = "recon-checked",
     KEPT: str = "recon-exception",
     REFUNDS: list[str] = ["refund", "refund_due", "reversal"],
     NOTE_MAX: int = 500,
     # A count may be corrected once, by whoever made it, this soon after (P15.6b).
     RECOUNT_SECONDS: int = 600,
     RECON_SECONDS: int = int(os.environ.get("AFRICINEMAS_RECON_SECONDS", "21600")),
     LABELS: dict[str, str] = {
         "not_paid": "Sold, but M-Pesa says it wasn't paid",
         "no_order": "Paid on M-Pesa, but nothing was sold",
         "amount_differs": "M-Pesa's amount differs from the sale",
         "receipt_twice": "One M-Pesa receipt on two payments",
         "cash_short": "Cash short at a cash-up",
         "cash_over": "Cash over at a cash-up",
         "cash_not_counted": "Cash not counted at the end of a shift"
     };

node ReconException {
    # One thing that doesn't add up. source: "mpesa" (the daily check) or "cash_up".
    # expected_cents is what AfriCinemas recorded, found_cents what M-Pesa or the count
    # found.
    has tenant_id: str,
        kind: str,
        source: str,
        reference: str = "",
        receipt: str = "",
        expected_cents: int = 0,
        found_cents: int = 0,
        detail: str = "",
        found_at: str = "",
        # What it's about, as keep() claimed it: a cash-up's is "member|when".
        about: str = "",
        status: str = "open",
        resolved_by: str = "",
        resolved_at: str = "",
        resolved_note: str = "";
}

node CashUp {
    # A member of staff's count: what they counted, what they'd recorded, since when.
    # first_counted_cents is what they counted before correcting it (-1: never
    # corrected).
    has tenant_id: str,
        member_id: str,
        member: str,
        counted_cents: int,
        expected_cents: int,
        since: str,
        at: str,
        first_counted_cents: int = -1,
        # Who counted it, when it isn't the member: the next at the venue, for cash
        # left by someone who didn't sign out (P15.6b).
        counted_by: str = "";
}

def exception_view(e: ReconException) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "exception_id": node_id(e),
        "kind": e.kind,
        "label": LABELS.get(e.kind, e.kind),
        "source": e.source,
        "reference": e.reference,
        "receipt": e.receipt,
        "expected_cents": e.expected_cents,
        "found_cents": e.found_cents,
        "detail": e.detail,
        "found_at": e.found_at,
        "status": e.status,
        "resolved_by": e.resolved_by,
        "resolved_at": e.resolved_at,
        "resolved_note": e.resolved_note
    };
}

def _as_cinema(cinema: Tenant, work: any) -> any {  # jac:ignore[W1037]
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        return work();
    } finally {
        restore(me);
    }
}

def exceptions_of(cinema: Tenant) -> list[ReconException] {
    found = _as_cinema(cinema, lambda -> any { return [cinema-->[?:ReconException]]; });  # jac:ignore[W1037]
    return sorted(
        found,
        key=lambda (e: ReconException) -> str { return e.found_at; },
        reverse=True
    );
}

def keep(  # jac:ignore[W3030] the exception: whose, what, why, about what, the amounts
    cinema: Tenant,
    kind: str,
    source: str,
    about: str,
    reference: str = "",
    receipt: str = "",
    expected: int = 0,
    found: int = 0,
    detail: str = ""
) -> bool {
    # Records the exception unless it's already kept (the same kind, about the same
    # thing); True when it's new.
    mine = fresh_node_id();
    if claim(KEPT, f"{node_id(cinema)}|{kind}|{about}", mine) != mine {
        return False;
    }
    def made -> any {  # jac:ignore[W1037]
        e = ReconException(
            tenant_id=node_id(cinema),
            kind=kind,
            source=source,
            reference=reference,
            receipt=receipt,
            expected_cents=expected,
            found_cents=found,
            detail=detail,
            found_at=now().isoformat(),
            about=about
        );
        cinema ++> e;
        attach_to_tenant(e, cinema);
        flush_now();
        return e;
    }
    _as_cinema(cinema, made);
    return True;
}

def resolve(cinema: Tenant, exception_id: str, note: str, who: str) -> ReconException {
    clean = " ".join(str(note or "").split());
    if not clean or len(clean) > NOTE_MAX {
        raise Refused(
            "invalid_note",
            f"Say how it was sorted out, in up to {NOTE_MAX} characters."
        );
    }
    found = [
        e
        for e in exceptions_of(cinema)
        if node_id(e) == exception_id
    ];
    if len(found) == 0 {
        raise Refused("not_found", "There's no such exception.");
    }
    e = found[0];
    if e.status != "open" {
        raise Refused("already_resolved", "That's already resolved.");
    }
    def mark -> any {  # jac:ignore[W1037]
        e.status = "resolved";
        e.resolved_by = who;
        e.resolved_at = now().isoformat();
        e.resolved_note = clean;
        flush_now();
        return e;
    }
    _as_cinema(cinema, mark);
    return e;
}

def _orders(cinema: Tenant) -> list[Order] {
    # Every order of the cinema: its showtimes' and its venues' own (snacks only).
    def walk -> any {  # jac:ignore[W1037]
        found: list[Order] = [];
        for venue in [cinema-->[?:Venue]] {
            found.extend([venue-->[?:Order]]);
            for screen in [venue-->[?:Auditorium]] {
                for s in [screen-->[?:Screening]] {
                    found.extend([s-->[?:Order]]);
                }
            }
        }
        return found;
    }
    return _as_cinema(cinema, walk);
}

def _records(
    cinema: Tenant
) -> list[tuple[Order, list[PaymentIntent], list[LedgerEntry]]] {
    def read -> any {  # jac:ignore[W1037]
        return [
            (o, [o-->[?:PaymentIntent]], [o-->[?:LedgerEntry]]) for o in _orders(cinema)
        ];
    }
    return _as_cinema(cinema, read);
}

def _cash_entries(cinema: Tenant) -> list[tuple[str, LedgerEntry]] {
    # Every cash payment or refund, with the venue it was taken at.
    def walk -> any {  # jac:ignore[W1037]
        found: list[tuple[str, LedgerEntry]] = [];
        for venue in [cinema-->[?:Venue]] {
            vid = node_id(venue);
            orders: list[Order] = [venue-->[?:Order]];
            for screen in [venue-->[?:Auditorium]] {
                for sc in [screen-->[?:Screening]] {
                    orders.extend([sc-->[?:Order]]);
                }
            }
            for o in orders {
                for e in [o-->[?:LedgerEntry]] {
                    if e.method == "cash"
                        and e.recorded_by
                        and (e.kind == "payment" or e.kind in REFUNDS) {
                        found.append((vid, e));
                    }
                }
            }
        }
        return found;
    }
    return _as_cinema(cinema, walk);
}

def _recent(stamp: str, since: datetime) -> bool {
    if not stamp {
        return False;
    }
    try {
        return datetime.fromisoformat(stamp) >= since;
    } except ValueError {
        return False;
    }
}

def check_mpesa(cinema: Tenant, at: datetime) -> int {
    # The daily check: M-Pesa asked again about each recent payment; how many new
    # exceptions.
    since = at - timedelta(days=LOOKBACK_DAYS);
    made = 0;
    receipts: dict[str, list[str]] = {};
    for (order, intents, entries) in _records(cinema) {
        sold = {
            e.intent_id: e
            for e in entries
            if e.kind == "payment" and e.method == "mpesa" and e.amount_cents > 0
        };
        for e in sold.values() {
            if e.receipt {
                receipts.setdefault(e.receipt, []).append(order.reference);
            }
        }
        for intent in intents {
            if not intent.checkout_request_id
                or not _recent(intent.updated_at, since) {
                continue;
            }
            if intent.state
                not in [
                    "success",
                    "failed",
                    "cancelled",
                    "timeout",
                    "needs_attention"
                ] {
                continue;
            }
            ref = intent.reference;
            if claim(CHECKED, f"{node_id(cinema)}|{ref}", "1") != "1" {
                continue;
            }
            provider = provider_of(cinema, intent);
            if provider is None {
                continue;
            }
            status = provider.query(intent.checkout_request_id);
            # No answer yet, or M-Pesa doesn't know it (a prompt too old to ask about):
            # unchecked, so asked again next time while it's still recent.
            if status.state in [PaymentState.UNKNOWN, PaymentState.STK_REQUESTED] {
                release(CHECKED, f"{node_id(cinema)}|{ref}", "1");
                continue;
            }
            taken = sold.get(node_id(intent));
            paid = status.state == PaymentState.SUCCESS;
            if taken is not None and not paid {
                made += int(
                    keep(
                        cinema,
                        "not_paid",
                        "mpesa",
                        ref,
                        order.reference,
                        taken.receipt,
                        taken.amount_cents,
                        0,
                        status.result_text
                    )
                );
            } elif taken is None and paid {
                made += int(
                    keep(
                        cinema,
                        "no_order",
                        "mpesa",
                        ref,
                        order.reference,
                        status.receipt,
                        0,
                        status.amount_cents,
                        intent.attention_reason
                    )
                );
            } elif taken is not None
                and paid
                and status.amount_cents
                and status.amount_cents != taken.amount_cents {
                made += int(
                    keep(
                        cinema,
                        "amount_differs",
                        "mpesa",
                        ref,
                        order.reference,
                        status.receipt,
                        taken.amount_cents,
                        status.amount_cents
                    )
                );
            }
        }
    }
    for (receipt, refs) in receipts.items() {
        if len(refs) > 1 {
            made += int(
                keep(
                    cinema,
                    "receipt_twice",
                    "mpesa",
                    receipt,
                    ", ".join(sorted(refs)),
                    receipt,
                    0,
                    0,
                    f"{len(refs)} payments"
                )
            );
        }
    }
    return made;
}

def check_all(cinemas: list[Tenant], at: datetime) -> int {
    made = 0;
    for cinema in cinemas {
        try {
            made += check_mpesa(cinema, at);
        } except Exception as e {
            print(f"reconcile: {cinema.slug} failed: {e}");
        }
    }
    return made;
}

def cash_ups_of(cinema: Tenant) -> list[CashUp] {
    found = _as_cinema(cinema, lambda -> any { return [cinema-->[?:CashUp]]; });  # jac:ignore[W1037]
    return sorted(found, key=lambda (c: CashUp) -> str { return c.at; }, reverse=True);
}

def _last_count(cinema: Tenant, member_id: str) -> CashUp | None {
    mine = [
        c
        for c in cash_ups_of(cinema)
        if c.member_id == member_id
    ];
    return mine[0] if mine else None;
}

def uncounted_at(cinema: Tenant, member_id: str) -> tuple[int, str, str, list[str]] {
    # The cash the member recorded since their last count, the first and last time
    # they recorded any ("" when there's none), and the venues it was taken at. A sale
    # and its refund still count as cash handled.
    last = _last_count(cinema, member_id);
    since = last.at if last is not None else "";
    expected = 0;
    first = "";
    latest = "";
    venues: list[str] = [];
    for (venue_id, e) in _cash_entries(cinema) {
        if e.recorded_by != member_id or (since and e.created_at <= since) {
            continue;
        }
        expected += e.amount_cents;
        if not first or e.created_at < first {
            first = e.created_at;
        }
        if e.created_at > latest {
            latest = e.created_at;
        }
        if venue_id not in venues {
            venues.append(venue_id);
        }
    }
    return (expected, first, latest, venues);
}

def uncounted(cinema: Tenant, member_id: str) -> tuple[int, str, str] {
    (expected, first, latest, _) = uncounted_at(cinema, member_id);
    return (expected, first, latest);
}

def left_behind(  # jac:ignore[W3030] whose cinema, who asks, where they sell, who's on
    cinema: Tenant,
    me: str,
    my_venues: list[str] | None,
    still_on: any,  # jac:ignore[W1037]
    names: dict[str, str]
) -> list[dict[str, any]] {  # jac:ignore[W1037]
    # Others' uncounted cash at the venues `me` sells at (None: all of them), for the
    # next at the venue to count (owner's decision, 2026-10-29). `still_on(member_id)`
    # says whether that member is still on shift: if so it's only offered (they may
    # still be working); once it's over it must be counted before the next cash sale.
    members: list[str] = [];
    for (_, e) in _cash_entries(cinema) {
        if e.recorded_by != me and e.recorded_by not in members {
            members.append(e.recorded_by);
        }
    }
    found: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for member_id in sorted(members) {
        (_, first, latest, venues) = uncounted_at(cinema, member_id);
        if not first {
            continue;
        }
        if my_venues is not None and not any([v in my_venues for v in venues]) {
            continue;
        }
        found.append(
            {
                "member_id": member_id,
                "member": names.get(member_id, member_id),
                "on_shift": bool(still_on(member_id)),
                "last_sale_at": latest
            }
        );
    }
    return found;
}

def count_first(cinema: Tenant, member_id: str, started_at: str) -> bool {
    # Cash from before the member's shift started is still uncounted: they're asked to
    # count it before selling for cash again.
    (_, first, _) = uncounted(cinema, member_id);
    return bool(first) and bool(started_at) and first < started_at;
}

def require_counted(  # jac:ignore[W3030] whose cinema, who sells, since when, what's left
    cinema: Tenant,
    member_id: str,
    started_at: str,
    behind: list[dict[str, any]]  # jac:ignore[W1037]
) {
    # Before a cash sale (P15.6b): cash from the member's own earlier shift, and cash
    # left at their venue by someone whose shift is over, must be counted first.
    if count_first(cinema, member_id, started_at) {
        raise Refused(
            "count_first",
            "Count the cash from your last shift first, on Box office → Count cash."
        );
    }
    gone = [
        b["member"]
        for b in behind
        if not b["on_shift"]
    ];
    if gone {
        raise Refused(
            "count_left",
            f"{gone[
                0
            ]} didn't count their cash before leaving. Count it first, on Box office → Count cash."
        );
    }
}

def staff_names(cinema: Tenant) -> dict[str, str] {
    # Member ids to how they're shown: their sign-in email, else the id.
    def read -> any {  # jac:ignore[W1037]
        return {
            m.staff_root_id: m.email or m.staff_root_id for m in records_of(cinema)
        };
    }
    return _as_cinema(cinema, read);
}

def selling_venues(scope: any) -> list[str] | None {  # jac:ignore[W1037]
    # The venues the caller sells at; None when it's all of them.
    venues: list[str] = [];
    for a in scope.ctx.assignments {
        if "bookings.create" not in ROLE_PERMISSIONS[a.role] {
            continue;
        }
        if a.venue_ids is None {
            return None;
        }
        venues.extend(a.venue_ids);
    }
    return venues;
}

def behind_for(scope: any) -> list[dict[str, any]] {  # jac:ignore[W1037]
    # Cash others left uncounted at the caller's venues (left_behind).
    tid = scope.ctx.tenant_id;
    return left_behind(
        scope.tenant,
        scope.ctx.member_root_id,
        selling_venues(scope),
        lambda (member_id: str) -> bool { return shift_is_open(tid, member_id); },
        staff_names(scope.tenant)
    );
}

def check_cash_sale(scope: any) {  # jac:ignore[W1037]
    # Before a cash sale: nothing left uncounted (require_counted).
    me = scope.ctx.member_root_id;
    require_counted(
        scope.tenant, me, shift_started_at(scope.ctx.tenant_id, me), behind_for(scope)
    );
}

def _check_amount(cinema: Tenant, counted: int) {
    if isinstance(counted, bool) or not isinstance(counted, int) or counted < 0 {
        raise Refused("invalid_amount", "Enter the cash you counted, in shillings.");
    }
    if counted > cinema.cash_count_max_cents {
        raise Refused(
            "too_much",
            f"That's more than KES {cinema.cash_count_max_cents
                // 100:,}, the most one count can be. Check the amount, or ask your manager to raise the limit."
        );
    }
}

def _settle(cinema: Tenant, about: str, note: str) {
    # Marks the open cash exceptions about `about` resolved, by the count itself.
    def run {
        for e in [cinema-->[?:ReconException]] {
            if e.status == "open" and e.about == about {
                e.status = "resolved";
                e.resolved_by = "the count";
                e.resolved_at = now().isoformat();
                e.resolved_note = note;
            }
        }
        flush_now();
    }
    _as_cinema(cinema, run);
}

def _keep_difference(cinema: Tenant, c: CashUp, about: str) {
    if c.counted_cents != c.expected_cents {
        keep(
            cinema,
            "cash_short" if c.counted_cents < c.expected_cents else "cash_over",
            "cash_up",
            about,
            "",
            "",
            c.expected_cents,
            c.counted_cents,
            f"{c.member}, counted by {c.counted_by}" if c.counted_by else c.member
        );
    }
}

def cash_up(  # jac:ignore[W3030] whose cinema, whose cash, their name, how much, by whom
    cinema: Tenant, member_id: str, member: str, counted: int, counted_by: str = ""
) -> CashUp {
    # The member's count against the cash they recorded since their last cash-up, by
    # them or (counted_by) by the next at the venue. A "not counted" exception for that
    # cash is settled by it.
    _check_amount(cinema, counted);
    last = _last_count(cinema, member_id);
    since = last.at if last is not None else "";
    (expected, _, _) = uncounted(cinema, member_id);
    at = now().isoformat();
    def made -> any {  # jac:ignore[W1037]
        c = CashUp(
            tenant_id=node_id(cinema),
            member_id=member_id,
            member=member,
            counted_cents=counted,
            expected_cents=expected,
            since=since,
            at=at,
            counted_by=counted_by
        );
        cinema ++> c;
        attach_to_tenant(c, cinema);
        flush_now();
        return c;
    }
    done = _as_cinema(cinema, made);
    _keep_difference(cinema, done, f"{member_id}|{at}");
    _settle(
        cinema,
        f"{member_id}|{since}|uncounted",
        f"Counted later by {counted_by}: KES {counted // 100:,}."
            if counted_by
            else f"Counted later: KES {counted // 100:,}."
    );
    return done;
}

def recount(cinema: Tenant, member_id: str, counted: int) -> CashUp {
    # Corrects the member's last count, once, within RECOUNT_SECONDS of making it. Both
    # figures are kept; the first count's exception is settled and the new one's kept.
    _check_amount(cinema, counted);
    last = _last_count(cinema, member_id);
    if last is None
        or last.counted_by
        or last.first_counted_cents >= 0
        or (now() - datetime.fromisoformat(last.at)).total_seconds()
            > RECOUNT_SECONDS {
        raise Refused(
            "too_late",
            "A count can be corrected once, within 10 minutes. Ask your manager to sort it out on the Reconciliation page."
        );
    }
    first = last.counted_cents;
    def change -> any {  # jac:ignore[W1037]
        last.first_counted_cents = first;
        last.counted_cents = counted;
        flush_now();
        return last;
    }
    done = _as_cinema(cinema, change);
    _settle(
        cinema,
        f"{member_id}|{last.at}",
        f"Recounted: KES {counted // 100:,} (first counted KES {first // 100:,})."
    );
    _keep_difference(cinema, done, f"{member_id}|{last.at}|recount");
    return done;
}

def check_uncounted(
    cinema: Tenant,
    names: dict[str, str],
    still_on: any  # jac:ignore[W1037]
) -> int {
    # Staff whose shift has ended (signed out, or it ran out) with cash they haven't
    # counted: `cash_not_counted`, once per uncounted stretch. `still_on(member_id)`
    # says whether their shift is open; `names` maps member ids to how they're shown.
    members: set[str] = set();
    for (_, e) in _cash_entries(cinema) {
        members.add(e.recorded_by);
    }
    made = 0;
    for member_id in sorted(members) {
        if still_on(member_id) {
            continue;
        }
        (expected, first, _) = uncounted(cinema, member_id);
        if not first {
            continue;
        }
        last = _last_count(cinema, member_id);
        since = last.at if last is not None else "";
        made += int(
            keep(
                cinema,
                "cash_not_counted",
                "cash_up",
                f"{member_id}|{since}|uncounted",
                "",
                "",
                expected,
                0,
                names.get(member_id, member_id)
            )
        );
    }
    return made;
}

def cash_up_view(c: CashUp) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "member": c.member,
        "counted_cents": c.counted_cents,
        "first_counted_cents": c.first_counted_cents,
        "expected_cents": c.expected_cents,
        "difference_cents": c.counted_cents - c.expected_cents,
        "since": c.since,
        "at": c.at,
        "counted_by": c.counted_by,
        "recount_until": (
            datetime.fromisoformat(c.at) + timedelta(seconds=RECOUNT_SECONDS)
        ).isoformat()
            if c.first_counted_cents < 0
            else ""
    };
}
