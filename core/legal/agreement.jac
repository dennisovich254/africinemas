"""Which version of the cinema agreement each cinema accepted (P15.1, ADR-0079).

The current version is the published one (core/legal/legal_api.jac, VERSION). A
cinema's acceptance is one permanent claim per cinema: the version, who accepted it
(the owner's account and email) and when, with every earlier acceptance kept in its
history.

may_sell is the rule order placement follows (require_live): a cinema that accepted an
older version can't take orders until its owner accepts the current one. A cinema that
has never accepted can't go live, since submitting for review needs the current version
accepted (verification's essentials); cinemas made before P15.1 accept at their owner's
next visit.

Kept apart from agreement_api.jac so require_live imports nothing heavy.
"""

import json;
import from core.claims { claim, holder, take_claim }
import from core.tenancy.models { Tenant }
import from core.tenancy.principal { node_id }
import from core.legal.legal_api { VERSION }

glob SPACE: str = "cinema-agreement",
     # Tests only (payment_app.jac, t_agreement_version): a newer current version.
     _published: list[str] = [];

def current_version -> str {
    return _published[0] if len(_published) > 0 else VERSION;
}

def set_current_version(version: str) {
    # Tests only: as if `version` had been published ("" goes back to VERSION).
    _published.clear();
    if version {
        _published.append(version);
    }
}

def acceptance_of(cinema: Tenant) -> dict[str, any] | None {  # jac:ignore[W1037]
    # {"version", "by", "email", "at", "history": [earlier acceptances]}, or None.
    kept = holder(SPACE, node_id(cinema));
    return json.loads(kept) if kept else None;
}

def accepted_current(cinema: Tenant) -> bool {
    found = acceptance_of(cinema);
    return found is not None and found["version"] == current_version();
}

def may_sell(cinema: Tenant) -> bool {
    # False only when an older version was accepted and the current one hasn't been.
    found = acceptance_of(cinema);
    return found is None or found["version"] == current_version();
}

def record_acceptance(cinema: Tenant, who: str, email: str, at: str) -> dict[str, any] {  # jac:ignore[W1037]
    earlier = acceptance_of(cinema);
    history: list[dict[str, str]] = [];
    if earlier is not None {
        history = list(earlier.get("history", []));
        history.append(
            {
                "version": earlier["version"],
                "by": earlier["by"],
                "email": earlier["email"],
                "at": earlier["at"]
            }
        );
    }
    kept = {
        "version": current_version(),
        "by": who,
        "email": email,
        "at": at,
        "history": history
    };
    key = node_id(cinema);
    take_claim(SPACE, key);
    claim(SPACE, key, json.dumps(kept));
    return kept;
}
