"""Accepting the cinema agreement (P15.1, ADR-0079).

- cinema_agreement_status(tenant): for any member of the cinema's team; the current
  version, what was accepted (version, by whom, when) and whether the owner needs to
  accept, and whether the cinema may sell.
- cinema_agreement_text(tenant): the agreement itself (confidential), for the cinema's
  own team only, to read before accepting.
- accept_cinema_agreement(tenant, version): the owner only (tenant.verification),
  without needing a shift, since it's the first thing after creating a cinema; the
  version must be the current one, so nobody accepts text they didn't see. Recorded in
  the cinema's audit log.
"""

import from core.clock { now }
import from core.authz.context { resolve_context }
import from core.authz.policy { Resource, require }
import from core.catalog.answers { Refused, answer }
import from core.audit.log { audited }
import from core.tenancy.principal { node_id }
import from core.tenancy.identity { verified_sign_in }
import from core.legal.legal_api { document_text, APPLIES_FROM, REVIEW_NOTE }
import from core.legal.agreement {
    acceptance_of,
    accepted_current,
    current_version,
    may_sell,
    record_acceptance
}

glob OWNER: str = "tenant.verification";

def _may_accept(scope: any) -> bool {  # jac:ignore[W1037]
    try {
        require(scope.ctx, OWNER, Resource(tenant_id=scope.ctx.tenant_id));
    } except Exception {
        return False;
    }
    return True;
}

def _status(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = resolve_context(tenant);
    cinema = scope.tenant;
    found = acceptance_of(cinema);
    return {
        "ok": True,
        "current": current_version(),
        "accepted": (
            {"version": found["version"], "email": found["email"], "at": found["at"]}
                if found is not None
                else None
        ),
        "needs_acceptance": not accepted_current(cinema),
        "may_sell": may_sell(cinema),
        "may_accept": _may_accept(scope)
    };
}

def _accept(tenant: str, version: str, sign_in: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = resolve_context(tenant);
    require(scope.ctx, OWNER, Resource(tenant_id=scope.ctx.tenant_id));
    if version != current_version() {
        raise Refused(
            "agreement_changed",
            "The agreement has changed since you opened it. Read the new version, then accept it."
        );
    }
    email = verified_sign_in(sign_in) if sign_in else "";
    kept = record_acceptance(scope.tenant, node_id(root), email, now().isoformat());
    return {"ok": True, "version": kept["version"], "at": kept["at"]};
}

def _text(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    resolve_context(tenant);
    return {
        "ok": True,
        "version": current_version(),
        "applies_from": APPLIES_FROM,
        "note": REVIEW_NOTE,
        "text": document_text("cinema-agreement")
    };
}

def:protect cinema_agreement_text(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _text(tenant); });  # jac:ignore[W1037]
}

def:protect cinema_agreement_status(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _status(tenant); });  # jac:ignore[W1037]
}

def:protect accept_cinema_agreement(
    tenant: str, version: str, sign_in: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "cinema.agreement_accepted",
        "cinema_agreement",
        str(version),
        lambda -> any { return _accept(tenant, version, sign_in); }  # jac:ignore[W1037]
    );
}
