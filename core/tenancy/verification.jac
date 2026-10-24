"""Verifying a cinema's owner and business (P14.4, ADR-0070), before it can go public.

The owner (only: `tenant.verification`, which no other role holds) fills the
Verification page:
- **the owner:** legal name as on their ID, ID or passport number, phone, and photos
  of the ID's front and back;
- **the business:** registered name, type, registration number, KRA PIN (a letter, nine
  digits, a letter), registration certificate, KRA PIN certificate, county business
  permit with its expiry date, and premises address.

The details are checked on the server, every problem at once. Each file is an image
(re-encoded, as photos are) or a PDF (rebuilt from its pages, core/catalog/documents.jac),
kept under a random name in the cinema's media and only ever served through
verification_file, to the owner (here) and to platform reviewers (14.5). Never a public
URL.

**Submit for review** needs every detail and file, the owner's email confirmed (14.2),
and the go-live essentials (§135): a venue, a screen with a published seat layout,
prices, and the required policies (14.3b). It moves the cinema from `configuring` to
`ready_for_go_live`, and the details can't be changed until a reviewer answers (14.5).
How long files are kept (decided 2026-10-24): ID photos 90 days after approval; the
business documents while the cinema is active and a year after it closes (14.5 does the
deleting, with approval).
"""

import io;
import re;
import base64;
import from datetime { date }
import from uuid { uuid4 }
import from core.clock { now }
import from core.authz.context { scoped, TenantScope }
import from core.tenancy.models { Tenant }
import from core.tenancy.state { TenantState, transition }
import from core.tenancy.groups { attach_to_tenant }
import from core.tenancy.principal { node_id, act_as, restore, flush_now }
import from core.tenancy.identity { verified_sign_in }
import from core.catalog.answers { Refused, answer }
import from core.catalog.poster {
    media_store,
    read_media,
    process_photo,
    PosterRejected
}
import from core.catalog.documents { decode_pdf, process_pdf, PdfRejected }
import from core.catalog.site_info { kenyan_number }
import from core.catalog.policies { missing_policies, title_of }
import from core.accounts.email_verification { is_confirmed }
import from core.reporting.staff_home { setup_of }
import from core.audit.log { audited }

glob VERIFY: str = "tenant.verification",
     TEXT_FIELDS: dict[str, tuple[str, int]] = {
         "legal_name": ("Your full name, as on your ID", 120),
         "id_number": ("ID or passport number", 20),
         "registered_name": ("The business's registered name", 160),
         "registration_number": ("Registration number", 40),
         "premises_address": ("The cinema's address", 200)
     },
     BUSINESS_TYPES: dict[str, str] = {
         "sole_proprietor": "Sole proprietor",
         "partnership": "Partnership",
         "limited_company": "Limited company"
     },
     FILES: dict[str, str] = {
         "id_front": "Your ID, front",
         "id_back": "Your ID, back",
         "registration_certificate": "Registration certificate",
         "kra_certificate": "KRA PIN certificate",
         "county_permit": "County business permit"
     },
     KRA_PIN: str = r"[A-Z][0-9]{9}[A-Z]",
     ID_NUMBER: str = r"[A-Z0-9]{6,12}",
     IMAGE_TYPES: list[str] = ["image/jpeg", "image/png", "image/webp"],
     # Who may change the details: until submitted, and again when changes are asked.
     EDITABLE: list[str] = ["draft", "changes_requested"],
     ESSENTIALS: list[tuple[str, str]] = [
         ("venue", "Add a venue"),
         ("screen", "Publish a screen's seat layout"),
         ("prices", "Set your ticket prices")
     ];

node Verification {
    # The cinema's verification record. details: the fields above; files: item ->
    # {key, type ("image" or "pdf"), uploaded_at}; status: draft, submitted, approved,
    # changes_requested or rejected (14.5); reasons: a reviewer's, when asked to change.
    # Owned by the cinema's principal.
    has tenant_id: str,
        details: dict[str, str] = {},
        files: dict[str, dict[str, str]] = {},
        status: str = "draft",
        submitted_at: str = "",
        reasons: list[str] = [];
}

obj Problem {
    has field: str,
        message: str;
}

def clean_details(raw: any) -> tuple[dict[str, str], list[Problem]] {  # jac:ignore[W1037]
    # The details as kept, and every problem with what was sent. Empty is allowed here
    # (a draft); what's missing is for submitting.
    given: dict[str, any] = raw if isinstance(raw, dict) else {};  # jac:ignore[W1037]
    out: dict[str, str] = {};
    problems: list[Problem] = [];
    for (field, (label, limit)) in TEXT_FIELDS.items() {
        text = " ".join(str(given.get(field, "") or "").split());
        if "<" in text or ">" in text {
            problems.append(
                Problem(field=field, message="Use plain text, without < or >.")
            );
        } elif len(text) > limit {
            problems.append(
                Problem(field=field, message=f"Keep it to {limit} characters or fewer.")
            );
        }
        out[field] = text;
    }
    id_number = "".join(out["id_number"].upper().split());
    if id_number and not re.fullmatch(ID_NUMBER, id_number) {
        problems.append(
            Problem(
                field="id_number",
                message="Enter the number on your ID or passport: 6 to 12 letters and digits."
            )
        );
    }
    out["id_number"] = id_number;
    phone_typed = str(given.get("phone", "") or "").strip();
    out["phone"] = kenyan_number(phone_typed) if phone_typed else "";
    if phone_typed and not out["phone"] {
        problems.append(
            Problem(
                field="phone", message="Enter a Kenyan phone number, like 0712 345 678."
            )
        );
    }
    kind = str(given.get("business_type", "") or "");
    if kind and kind not in BUSINESS_TYPES {
        problems.append(
            Problem(field="business_type", message="Choose the type of business.")
        );
        kind = "";
    }
    out["business_type"] = kind;
    pin = "".join(str(given.get("kra_pin", "") or "").upper().split());
    if pin and not re.fullmatch(KRA_PIN, pin) {
        problems.append(
            Problem(
                field="kra_pin",
                message="A KRA PIN is a letter, 9 digits and a letter, like A123456789B."
            )
        );
    }
    out["kra_pin"] = pin;
    expiry = str(given.get("permit_expiry", "") or "").strip();
    if expiry {
        try {
            date.fromisoformat(expiry);
        } except ValueError {
            problems.append(
                Problem(
                    field="permit_expiry", message="Enter the permit's expiry date."
                )
            );
            expiry = "";
        }
    }
    out["permit_expiry"] = expiry;
    return (out, problems);
}

def missing_details(
    details: dict[str, str], files: dict[str, dict[str, str]], today: str
) -> list[dict[str, str]] {  # jac:ignore[W1037]
    # What submitting still needs: [{field, message}], empty when complete.
    missing: list[dict[str, str]] = [];
    for (field, (label, _)) in TEXT_FIELDS.items() {
        if not details.get(field, "") {
            missing.append({"field": field, "message": f"{label} is needed."});
        }
    }
    for (field, label) in [
        ("phone", "Your phone number"),
        ("business_type", "The type of business"),
        ("kra_pin", "The KRA PIN"),
        ("permit_expiry", "The permit's expiry date")
    ] {
        if not details.get(field, "") {
            missing.append({"field": field, "message": f"{label} is needed."});
        }
    }
    expiry = details.get("permit_expiry", "");
    if expiry and expiry <= today {
        missing.append(
            {
                "field": "permit_expiry",
                "message": "The county permit has expired. Upload the current one."
            }
        );
    }
    for (item, label) in FILES.items() {
        if item not in files {
            missing.append({"field": item, "message": f"{label} is needed."});
        }
    }
    return missing;
}

def verification_key(tenant_id: str, ext: str) -> str {
    # Private files: their own folder, random names, never served as a URL.
    return f"tenant/{tenant_id}/verification/{uuid4()}.{ext}";
}

def _kept(cinema: Tenant) -> Verification | None {
    if not cinema.verification_id {
        return None;
    }
    try {
        found: any = jobj(cinema.verification_id);  # jac:ignore[W1037]
    } except Exception {
        return None;
    }
    return found if isinstance(found, Verification) else None;
}

def record_of(cinema: Tenant) -> dict[str, any] {  # jac:ignore[W1037]
    # The record as plain data: details, files, status, submitted_at, reasons.
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = _kept(cinema);
        if found is None {
            return {
                "details": {},
                "files": {},
                "status": "draft",
                "submitted_at": "",
                "reasons": []
            };
        }
        return {
            "details": dict(found.details),
            "files": {k: dict(v) for (k, v) in found.files.items()},
            "status": found.status,
            "submitted_at": found.submitted_at,
            "reasons": list(found.reasons)
        };
    } finally {
        restore(me);
    }
}

def _write(cinema: Tenant, tenant_id: str, changes: dict[str, any]) {  # jac:ignore[W1037]
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = _kept(cinema);
        if found is None {
            made = Verification(tenant_id=tenant_id);
            cinema ++> made;
            attach_to_tenant(made, cinema);
            cinema.verification_id = node_id(made);
            found = made;
        }
        kept: Verification = found;
        if "details" in changes {
            kept.details = changes["details"];
        }
        if "files" in changes {
            kept.files = changes["files"];
        }
        if "status" in changes {
            kept.status = changes["status"];
        }
        if "submitted_at" in changes {
            kept.submitted_at = changes["submitted_at"];
        }
        flush_now();
    } finally {
        restore(me);
    }
}

def _essentials(cinema: Tenant) -> list[dict[str, str]] {
    # The go-live essentials not yet done (§135), with where to do them.
    done = {s["key"]: s["done"] for s in setup_of(cinema)["steps"]};
    gaps = [
        {"field": key, "message": label}
        for (key, label) in ESSENTIALS
        if not done.get(key, False)
    ];
    for kind in missing_policies(cinema) {
        gaps.append(
            {"field": "policies", "message": f"Publish your {title_of(kind).lower()}"}
        );
    }
    return gaps;
}

def _view(cinema: Tenant) -> dict[str, any] {  # jac:ignore[W1037]
    kept = record_of(cinema);
    today = now().date().isoformat();
    return {
        "ok": True,
        "status": kept["status"],
        "state": cinema.state,
        "submitted_at": kept["submitted_at"],
        "reasons": kept["reasons"],
        "details": kept["details"],
        "files": {
            k: {"type": v["type"], "uploaded_at": v["uploaded_at"]}
            for (k, v) in kept["files"].items()
        },
        "missing": missing_details(kept["details"], kept["files"], today),
        "essentials": _essentials(cinema),
        "editable": kept["status"] in EDITABLE
    };
}

def _owner(tenant: str) -> TenantScope {
    return scoped(tenant, VERIFY);
}

def _editable(cinema: Tenant) {
    if record_of(cinema)["status"] not in EDITABLE {
        raise Refused(
            "under_review",
            "Your details are with AfriCinemas for review, so they can't be changed now."
        );
    }
}

def _get(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return _view(_owner(tenant).tenant);
}

def _save(tenant: str, details: any) -> dict[str, any] {  # jac:ignore[W1037]
    scope = _owner(tenant);
    _editable(scope.tenant);
    (clean, problems) = clean_details(details);
    if problems {
        raise Refused(
            "invalid_details",
            "Some of this needs fixing before it can be saved.",
            {"problems": [{"field": p.field, "message": p.message} for p in problems]}
        );
    }
    _write(scope.tenant, scope.ctx.tenant_id, {"details": clean});
    return _view(scope.tenant);
}

def checked_file(content_type: str, data_base64: str) -> tuple[bytes, str] {
    # An ID photo or a certificate, checked and rebuilt: (bytes, "image" | "pdf").
    try {
        data = decode_pdf(data_base64);
        if content_type == "application/pdf" {
            return (process_pdf(data), "pdf");
        }
        if content_type not in IMAGE_TYPES {
            raise Refused("wrong_type", "Choose a photo (JPEG, PNG or WebP) or a PDF.");
        }
        return (process_photo(data, content_type), "image");
    } except PdfRejected as e {
        raise Refused(e.code, e.message);
    } except PosterRejected as e {
        raise Refused(e.code, e.message);
    }
}

def _upload(
    tenant: str, item: str, content_type: str, data_base64: str
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = _owner(tenant);
    if item not in FILES {
        raise Refused("unknown_item", "Choose one of the documents listed.");
    }
    _editable(scope.tenant);
    (clean, kind) = checked_file(content_type, data_base64);
    key = verification_key(scope.ctx.tenant_id, "pdf" if kind == "pdf" else "webp");
    media_store().upload(io.BytesIO(clean), key);
    files = record_of(scope.tenant)["files"];
    old = files.get(item, {}).get("key", "");
    files[item] = {"key": key, "type": kind, "uploaded_at": now().isoformat()};
    try {
        _write(scope.tenant, scope.ctx.tenant_id, {"files": files});
    } except Exception as e {
        media_store().delete(key);
        raise e;
    }
    if old {
        on_commit(lambda { media_store().delete(old); });
    }
    return _view(scope.tenant);
}

def file_answer(cinema: Tenant, item: str) -> dict[str, any] {  # jac:ignore[W1037]
    # One of the cinema's verification files, for whoever may see it (the owner here,
    # platform reviewers in 14.5): its type and the file as base64.
    found = record_of(cinema)["files"].get(item, {});
    data = read_media(found.get("key", ""));
    if not data {
        raise Refused("no_file", "That document hasn't been uploaded.");
    }
    return {
        "ok": True,
        "item": item,
        "type": found["type"],
        "file": base64.b64encode(data).decode()
    };
}

def _submit(tenant: str, email: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = _owner(tenant);
    cinema = scope.tenant;
    _editable(cinema);
    mine = verified_sign_in(email) if email else "";
    if not mine or "@" not in mine or not is_confirmed(node_id(root), mine) {
        raise Refused(
            "email_unverified", "Confirm your email first: we sent you a link."
        );
    }
    view = _view(cinema);
    if view["missing"] or view["essentials"] {
        raise Refused(
            "not_ready",
            "A few things are still needed before AfriCinemas can review your cinema.",
            {"missing": view["missing"], "essentials": view["essentials"]}
        );
    }
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        if cinema.state == TenantState.CONFIGURING.value {
            cinema.state = transition(
                TenantState(cinema.state), TenantState.READY_FOR_GO_LIVE
            ).value;
        }
        flush_now();
    } finally {
        restore(me);
    }
    _write(
        cinema,
        scope.ctx.tenant_id,
        {"status": "submitted", "submitted_at": now().isoformat()}
    );
    return _view(cinema);
}

def:protect verification(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _get(tenant); });  # jac:ignore[W1037]
}

def:protect save_verification(tenant: str, details: dict[str, any]) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "verification.saved",
        "verification",
        "",
        lambda -> any { return _save(tenant, details); }  # jac:ignore[W1037]
    );
}

def:protect upload_verification_file(
    tenant: str, item: str, content_type: str, data_base64: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "verification.file_uploaded",
        "verification",
        item,
        lambda -> any { return _upload(tenant, item, content_type, data_base64); }  # jac:ignore[W1037]
    );
}

def:protect verification_file(tenant: str, item: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The owner's own look at a file they uploaded.
    return answer(
        lambda -> any { return file_answer(_owner(tenant).tenant, item); }  # jac:ignore[W1037]
    );
}

def:protect submit_verification(tenant: str, email: str) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "verification.submitted",
        "verification",
        "",
        lambda -> any { return _submit(tenant, email); }  # jac:ignore[W1037]
    );
}
