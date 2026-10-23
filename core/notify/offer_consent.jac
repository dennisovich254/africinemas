"""Customers who asked a cinema for its offers (P14.3c, ADR-0068).

Kenya's Data Protection Act, 2019 lets a cinema send offers only to people who agreed,
and asks it to be able to show when and how they did. So consent is recorded only when
the customer ticks the box (never ticked for them), one record per email at each cinema,
with when it was given, where ("checkout", "signup" or "account") and the order's
reference when it came with one: a permanent claim per cinema and email
("offer-consent:<tenant id>", keyed by the email). Withdrawing keeps the record,
marked withdrawn, as the proof that we stopped. The box only shows when the cinema says it sends offers
(Website information, sends_offers).

A signed-in customer reads and changes theirs from My account (my_offers,
set_my_offers); at checkout it comes with the payment (start_payment's `offers`).
"""

import json;
import from core.clock { now }
import from core.claims { claim, holder, take_claim }
import from core.tenancy.models { Tenant }
import from core.tenancy.principal { node_id }
import from core.tenancy.open_cinema { open_cinema }
import from core.tenancy.storefront_accounts { require_customer_of, account_of }
import from core.tenancy.responses { NOT_FOUND }
import from core.catalog.answers { Refused, answer }
import from core.catalog.site_info { site_info_of }

glob SOURCES: list[str] = ["checkout", "signup", "account"],
     # One permanent claim per cinema and email: the record, as JSON.
     CONSENTS: str = "offer-consent";

def sends_offers(cinema: Tenant) -> bool {
    return bool(site_info_of(cinema).get("sends_offers", False));
}

def _space(cinema: Tenant) -> str {
    return f"{CONSENTS}:{node_id(cinema)}";
}

def consent_of(cinema: Tenant, email: str) -> dict[str, str] | None {
    # The record for `email` at `cinema`: given_at, source, reference, withdrawn_at.
    kept = holder(_space(cinema), email.strip().lower());
    return json.loads(kept) if kept else None;
}

def has_consent(cinema: Tenant, email: str) -> bool {
    found = consent_of(cinema, email);
    return found is not None and not found.get("withdrawn_at", "");
}

def record_consent(
    cinema: Tenant, email: str, given: bool, source: str, reference: str = ""
) {
    # Records `email`'s agreement (given) or its withdrawal at `cinema`.
    address = email.strip().lower();
    if not address or source not in SOURCES {
        return;
    }
    stamp = now().isoformat();
    found = consent_of(cinema, address);
    if given {
        kept = {
            "given_at": stamp,
            "source": source,
            "reference": reference,
            "withdrawn_at": ""
        };
    } elif found is not None and not found.get("withdrawn_at", "") {
        kept = {** found, "withdrawn_at": stamp};
    } else {
        return;
    }
    take_claim(_space(cinema), address);
    claim(_space(cinema), address, json.dumps(kept, sort_keys=True));
}

def _mine(slug: str) -> tuple[Tenant, str] {
    require_customer_of(slug);
    cinema = open_cinema(slug);
    account = account_of(node_id(root)) or {};
    address = str(account.get("email", ""));
    if cinema is None or not address {
        raise Refused(
            "not_your_cinema", "Sign in with your account at this cinema to do that."
        );
    }
    return (cinema, address);
}

def _my_offers(slug: str) -> dict[str, any] {  # jac:ignore[W1037]
    (cinema, address) = _mine(slug);
    return {
        "ok": True,
        "sends_offers": sends_offers(cinema),
        "subscribed": has_consent(cinema, address)
    };
}

def _set_my_offers(slug: str, subscribed: bool, source: str) -> dict[str, any] {  # jac:ignore[W1037]
    (cinema, address) = _mine(slug);
    if subscribed and not sends_offers(cinema) {
        raise Refused("no_offers", "This cinema doesn't send offers.");
    }
    record_consent(
        cinema, address, bool(subscribed), "signup" if source == "signup" else "account"
    );
    return _my_offers(slug);
}

def:protect my_offers(slug: str) -> dict[str, any] {  # jac:ignore[W1037]
    # Whether the signed-in customer gets this cinema's offers.
    if open_cinema(slug) is None {
        return NOT_FOUND;
    }
    return answer(lambda -> any { return _my_offers(slug); });  # jac:ignore[W1037]
}

def:protect set_my_offers(
    slug: str, subscribed: bool, source: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    # The signed-in customer asks for this cinema's offers, or stops them. `source`
    # "signup" when ticked while signing up, else from My account.
    if open_cinema(slug) is None {
        return NOT_FOUND;
    }
    return answer(
        lambda -> any { return _set_my_offers(slug, subscribed, source); }  # jac:ignore[W1037]
    );
}
