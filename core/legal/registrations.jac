"""The registrations checklist (P15.0b, ADR-0078): what AfriCinemas registers outside
the app before going live (docs/legal/registrations-checklist.md), ticked in the
platform console.

A super admin (platform.settings) ticks an item with its reference (a certificate
number, a note) or unticks it; who did it and when is kept with it, one permanent claim
per item, and every change goes to the platform audit log.
"""

import json;
import from core.clock { now }
import from core.claims { claim, holder, take_claim }
import from core.catalog.answers { Refused, answer }
import from core.platform.staff_api { require_platform }
import from core.audit.log { platform_audited }

glob SPACE: str = "legal-registration",
     REFERENCE_MAX: int = 200,
     # (key, what, why).
     ITEMS: list[tuple[str, str, str]] = [
         (
             "company",
             "Company registered (Business Registration Service)",
             "Companies Act, 2015"
         ),
         ("kra_pin", "KRA PIN for the company", "Tax Procedures Act, 2015"),
         ("etims", "eTIMS for invoices to cinemas", "Tax Procedures Act, s.23"),
         (
             "vat",
             "VAT, once fees reach KES 5 million in 12 months",
             "VAT Act, 2013, s.34"
         ),
         ("odpc_controller", "ODPC: data controller", "Data Protection Act, s.18"),
         ("odpc_processor", "ODPC: data processor", "Data Protection Act, s.18"),
         ("dpo", "Data protection contact published", "Data Protection Act, s.24"),
         (
             "dpia",
             "Verification impact assessment (and ODPC submission if required)",
             "Data Protection Act, s.31"
         ),
         (
             "payments_advice",
             "Advice on payment-services authorisation",
             "National Payment System Act, 2011"
         ),
         ("paybill", "AfriCinemas' paybill live for invoices", "Safaricom Daraja"),
         ("county_permit", "County business permit", "County Finance Act"),
         ("trade_mark", "Trade mark \"AfriCinemas\" (KIPI)", "Trade Marks Act"),
         ("domain", "Domain africinemas.co.ke held by the company", "KeNIC"),
         ("advocate_review", "Advocate's review of the legal documents", ""),
         (
             "kfcb_advice",
             "KFCB: advice on posters and trailers online",
             "Films and Stage Plays Act, s.12, s.13"
         ),
         ("insurance", "Professional indemnity and cyber insurance", "")
     ];

def _keys -> list[str] {
    return [k for (k, _, _) in ITEMS];
}

def _state(key: str) -> dict[str, any] {  # jac:ignore[W1037]
    kept = holder(SPACE, key);
    return json.loads(kept) if kept else {"done": False};
}

def _list -> dict[str, any] {  # jac:ignore[W1037]
    require_platform("platform.settings");
    return {
        "ok": True,
        "items": [
            {"key": k, "what": what, "law": law, ** _state(k)}
            for (k, what, law) in ITEMS
        ]
    };
}

def _tick(key: str, done: bool, reference: str, who: str) -> dict[str, any] {  # jac:ignore[W1037]
    if key not in _keys() {
        raise Refused("not_found", "That isn't on the checklist.");
    }
    note = " ".join(str(reference or "").split());
    if len(note) > REFERENCE_MAX or "<" in note or ">" in note {
        raise Refused(
            "invalid_reference",
            f"Keep the reference to {REFERENCE_MAX} characters of plain text."
        );
    }
    kept = {"done": bool(done), "reference": note, "by": who, "at": now().isoformat()};
    take_claim(SPACE, key);
    claim(SPACE, key, json.dumps(kept));
    return {"ok": True, "item": {"key": key, ** kept}};
}

def:protect registrations_checklist -> dict[str, any] {  # jac:ignore[W1037]
    return answer(_list);
}

def:protect tick_registration(
    key: str, done: bool, reference: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    try {
        me = require_platform("platform.settings");
    } except Refused as e {
        return {"ok": False, "error": {"code": e.code, "message": e.message}};
    }
    return platform_audited(
        me.root_id,
        me.email,
        "platform.registration_ticked" if done else "platform.registration_unticked",
        "registration",
        str(key),
        lambda -> any { return _tick(key, done, reference, me.email); },  # jac:ignore[W1037]
        detail=str(reference or "")[:REFERENCE_MAX]
    );
}
