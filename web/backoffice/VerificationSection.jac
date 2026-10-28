"""`/app/:slug/verification`: the owner's details and the business's documents, for
AfriCinemas to check before the cinema goes public (P14.4, ADR-0070).

The owner alone sees it (`tenant.verification`). A notice says why each item is asked
for and how long it's kept. About you: legal name, ID or passport number, phone, the
ID's front and back (a photo from the phone's camera, or a PDF). Your business: its
registered name, type, registration number, KRA PIN, address, the county permit's
expiry date, and three certificates. Every problem the server finds shows beside its
field. "Before you submit" lists what's still needed, the go-live essentials included,
with links; Submit for review sends it all. Once submitted, it's read-only until
AfriCinemas answers (14.5).

Photos over MAX_PHOTO_BYTES are made smaller here before they're sent (a phone's camera
takes large ones); the server checks and re-encodes every file anyway.
"""

import from react { useState, useEffect }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.tenancy.verification {
    verification,  # jac:ignore[W2037] authenticated endpoint
    save_verification,  # jac:ignore[W2037]
    upload_verification_file,  # jac:ignore[W2037]
    submit_verification  # jac:ignore[W2037]
}
import from core.accounts.email_verification { send_email_check }  # jac:ignore[W2037]
import from ..auth.session { signed_in_email }
import from ..shell.AppLink { AppLink }
import from .form_parts { TextField, FieldError, read_as_base64, submit_with }
import from .PdfDrop { PdfDrop }
import from .nav { section_path }
import from ..site { storefront_address }

glob MAX_PHOTO_BYTES: int = 4 * 1024 * 1024,
     MAX_SIDE: int = 2400,
     ABOUT_YOU: list[tuple[str, str, str]] = [
         (
             "legal_name",
             "Your full name, as on your ID",
             "So we can match it to your ID."
         ),
         (
             "id_number",
             "ID or passport number",
             "Checked by a person at AfriCinemas against your ID photos."
         ),
         ("phone", "Your phone number", "A Kenyan number, like 0712 345 678.")
     ],
     BUSINESS: list[tuple[str, str, str]] = [
         (
             "registered_name",
             "The business's registered name",
             "As on its registration certificate."
         ),
         (
             "registration_number",
             "Registration number",
             "From the registration certificate."
         ),
         ("kra_pin", "KRA PIN", "A letter, 9 digits and a letter, like A123456789B."),
         ("premises_address", "The cinema's address", "Building, street and town.")
     ],
     TYPES: list[tuple[str, str]] = [
         ("sole_proprietor", "Sole proprietor"),
         ("partnership", "Partnership"),
         ("limited_company", "Limited company")
     ],
     ID_FILES: list[tuple[str, str]] = [
         ("id_front", "Your ID, front"),
         ("id_back", "Your ID, back")
     ],
     BUSINESS_FILES: list[tuple[str, str]] = [
         ("registration_certificate", "Registration certificate"),
         ("kra_certificate", "KRA PIN certificate"),
         ("county_permit", "County business permit")
     ],
     # Where each go-live essential is done.
     ESSENTIAL_SECTIONS: dict[str, str] = {
         "venue": "venues",
         "screen": "screens",
         "prices": "prices",
         "policies": "settings/policies",
         "agreement": "agreement"
     };

async def smaller_photo(file: any) -> str {  # jac:ignore[W1037]
    # A large photo as a JPEG of at most MAX_SIDE pixels a side, as base64.
    win: any = window;  # jac:ignore[W1037,W2001]
    bitmap: any = await win.createImageBitmap(file, {"imageOrientation": "from-image"});  # jac:ignore[W1037]
    scale = min(1.0, MAX_SIDE / max(bitmap.width, bitmap.height));
    canvas: any = win.document.createElement("canvas");  # jac:ignore[W1037,W6001]
    canvas.width = int(bitmap.width * scale);
    canvas.height = int(bitmap.height * scale);
    canvas.getContext("2d").drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    url: str = canvas.toDataURL("image/jpeg", 0.85);
    return url.split(",")[1];
}

def Notice -> JsxElement {
    return
        <details className="rounded-lg border bg-card p-4" data-testid="data-notice">
            <summary className="min-h-11 cursor-pointer content-center font-semibold">
                Why we ask, and how long we keep it
            </summary>
            <div className="flex flex-col gap-2 pt-2 text-sm text-muted-foreground">
                <p>
                    AfriCinemas checks that every cinema selling tickets here is a real business run by a real person, so customers can trust it. A person at AfriCinemas reads what you send; nobody else sees it, and it's never shown on your storefront.
                </p>
                <ul className="flex list-disc flex-col gap-1 pl-5">
                    <li>
                        Your ID photos: to match your name to your ID. We delete them 90 days after your cinema is approved, and keep only the date we checked them.
                    </li>
                    <li>
                        Your business's certificates and permit: to confirm the business and its KRA PIN. We keep them while your cinema is on AfriCinemas, and delete them a year after it leaves.
                    </li>
                    <li>Your phone number: so we can reach you about your cinema.</li>
                </ul>
                <p>
                    You can ask us what we hold about you, or to correct it, under Kenya's Data Protection Act, 2019, from Help.
                </p>
            </div>
        </details>;
}

def Status(view: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
    status: str = view["status"];
    if status == "submitted" {
        return
            <Alert data-testid="verification-status">
                <AlertDescription>
                    With AfriCinemas for review since {(view["submitted_at"] or "")[:10]}. We'll email you when it's done; until then these details can't be changed.
                </AlertDescription>
            </Alert>;
    }
    if status == "changes_requested" {
        reasons: list[str] = view["reasons"] or [];
        return
            <Alert variant="destructive" data-testid="verification-status">
                <AlertDescription>
                    AfriCinemas asked for changes:
                    <ul className="list-disc pl-5">
                        {[<li key={f"{i}"}>{r}</li> for (i, r) in enumerate(reasons)]}
                    </ul>
                </AlertDescription>
            </Alert>;
    }
    if status == "rejected" {
        refused: list[str] = view["reasons"] or [];
        return
            <Alert variant="destructive" data-testid="verification-status">
                <AlertDescription>
                    AfriCinemas couldn't verify your cinema, so it won't go public:
                    <ul className="list-disc pl-5">
                        {[<li key={f"{i}"}>{r}</li> for (i, r) in enumerate(refused)]}
                    </ul>
                    If you think this is a mistake, ask us from Help.
                </AlertDescription>
            </Alert>;
    }
    if status == "approved" {
        return
            <Alert data-testid="verification-status">
                <AlertDescription>Your cinema is verified and public.</AlertDescription>
            </Alert>;
    }
    # Public without a review (a super admin made it live): not verified, so no badge
    # and no M-Pesa of its own until these details are approved.
    if view["state"] == "active" {
        return
            <Alert data-testid="verification-status">
                <AlertDescription>
                    Your cinema is public, but AfriCinemas hasn't verified it yet. Send these details for review to get the Verified badge and to connect your own M-Pesa.
                </AlertDescription>
            </Alert>;
    }
    return <span className="hidden" data-testid="verification-status"/>;
}

def location_origin -> str {
    win: any = window;  # jac:ignore[W1037,W2001]
    return win.location.origin;
}

def ShareLink(slug: str) -> JsxElement {
    # Once verified (P14.5): where customers should find the real storefront. A badge
    # proves nothing on a copied site; the cinema's own channels pointing here do.
    [copied, set_copied] = useState(False);
    found = storefront_address(slug);
    # Off our domain (a tunnel, the desktop app) it's a path: make it a full address.
    address = found if "://" in found else f"{location_origin()}{found}";
    shown_address = address.split("://")[-1].rstrip("/");
    async def copy {
        try {
            win: any = window;  # jac:ignore[W1037,W2001]
            await win.navigator.clipboard.writeText(address);
            set_copied(True);
        } except Exception as e {
            console.warn("copy failed", e);
        }
    }
    return
        <section
            aria-labelledby="share-link"
            className="flex flex-col gap-3 rounded-lg border bg-card p-4"
            data-testid="share-link"
        >
            <h3 id="share-link" className="font-semibold">Share your real link</h3>
            <p className="text-sm text-muted-foreground">
                Put it on your official Instagram, Facebook, TikTok and WhatsApp, so customers find your real storefront and not a copy. Your storefront is only ever at this address.
            </p>
            <div className="flex flex-wrap items-center gap-2">
                <code
                    className="break-all rounded-md border bg-muted px-3 py-2 text-sm"
                    data-testid="share-address"
                >
                    {shown_address}
                </code>
                <Button
                    type="button"
                    variant="outline"
                    className="min-h-11 px-4"
                    data-testid="copy-link"
                    onClick={lambda { copy(); }}
                >
                    {"Copied" if copied else "Copy link"}
                </Button>
            </div>
        </section>;
}

def:pub VerificationSection(slug: str) -> JsxElement {
    [view, set_view] = useState(None);
    [details, set_details] = useState({});
    [problems, set_problems] = useState({});
    [busy, set_busy] = useState("");
    [message, set_message] = useState("");
    [failed, set_failed] = useState("");

    def seen(answer: any) {  # jac:ignore[W1037]
        set_view(answer);
        set_details(answer["details"]);
    }

    async def load {
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await verification(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("verification failed", e);
        }
        if answer is None {
            set_failed("We couldn't load this. Refresh the page to try again.");
        } elif not answer["ok"] {
            set_failed(answer["error"]["message"]);
        } else {
            set_failed("");
            seen(answer);
        }
    }
    def start {
        load();
    }
    useEffect(start, [slug]);

    def put(field: str, value: str) {
        copy: dict[str, str] = {** details};
        copy[field] = value;
        set_details(copy);
        set_message("");
    }

    def picked_type(e: any) {  # jac:ignore[W1037]
        put("business_type", e.target.value);
    }
    def picked_expiry(e: any) {  # jac:ignore[W1037]
        put("permit_expiry", e.target.value);
    }

    def refused(answer: any) {  # jac:ignore[W1037]
        found: dict[str, str] = {};
        for p in (answer["error"]["problems"] or []) {
            found[p["field"]] = p["message"];
        }
        set_problems(found);
        set_failed(answer["error"]["message"]);
    }

    async def save {
        set_busy("save");
        set_message("");
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await save_verification(slug, details);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("save_verification failed", e);
        }
        set_busy("");
        if answer is None {
            set_failed(
                "We couldn't reach AfriCinemas. Check your connection and try again."
            );
            return;
        }
        if not answer["ok"] {
            refused(answer);
            return;
        }
        set_problems({});
        set_failed("");
        seen(answer);
        set_message("Saved.");
    }

    async def upload(item: str, file: any) {  # jac:ignore[W1037]
        set_busy(item);
        set_message("");
        answer: any = None;  # jac:ignore[W1037]
        try {
            content_type: str = file.type;
            encoded = "";
            if content_type != "application/pdf" and file.size > MAX_PHOTO_BYTES {
                encoded = await smaller_photo(file);
                content_type = "image/jpeg";
            } else {
                encoded = await read_as_base64(file);
                if content_type != "application/pdf"
                    and not content_type.startswith("image/") {
                    content_type = "application/pdf";
                }
            }
            answer = await upload_verification_file(slug, item, content_type, encoded);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("upload failed", e);
        }
        set_busy("");
        if answer is None {
            set_failed("We couldn't upload it. Check your connection and try again.");
            return;
        }
        if not answer["ok"] {
            copy: dict[str, str] = {** problems};
            copy[item] = answer["error"]["message"];
            set_problems(copy);
            return;
        }
        copy: dict[str, str] = {** problems};
        copy[item] = "";
        set_problems(copy);
        set_failed("");
        set_view(answer);
    }

    async def resend {
        # A new confirmation link, to the email this browser signed in with (P14.2).
        address = signed_in_email();
        if not address {
            set_failed("Sign out and back in, then send a new link from here.");
            return;
        }
        set_busy("resend");
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await send_email_check(address);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("send_email_check failed", e);
        }
        set_busy("");
        if answer is None or not answer["ok"] {
            set_failed(
                answer["error"]["message"]
                    if answer is not None
                    else "We couldn't reach AfriCinemas. Try again."
            );
            return;
        }
        set_failed("");
        set_message(
            "Your email is already confirmed."
                if answer["confirmed"]
                else f"We sent a new link to {address}. Open it, then come back here."
        );
        if answer["confirmed"] {
            load();
        }
    }

    async def submit {
        set_busy("submit");
        set_message("");
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await submit_verification(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("submit failed", e);
        }
        set_busy("");
        if answer is None {
            set_failed(
                "We couldn't reach AfriCinemas. Check your connection and try again."
            );
            return;
        }
        if not answer["ok"] {
            # Not load(): it would clear the message before it's read.
            set_failed(answer["error"]["message"]);
            return;
        }
        set_failed("");
        seen(answer);
        set_message("Sent. We'll email you once AfriCinemas has checked it.");
    }

    if view is None {
        if failed {
            return
                <Alert variant="destructive">
                    <AlertDescription>{failed}</AlertDescription>
                </Alert>;
        }
        return
            <p role="status" className="flex items-center gap-2 text-muted-foreground">
                <Spinner aria-hidden="true"/>
                Loading…
            </p>;
    }
    shown: dict[str, any] = view;  # jac:ignore[W1037]
    typed: dict[str, str] = details;
    errors: dict[str, str] = problems;
    files: dict[str, dict[str, str]] = shown["files"];
    open: bool = shown["editable"];
    missing: list[dict[str, str]] = shown["missing"];
    essentials: list[dict[str, str]] = shown["essentials"];
    confirmed: bool = shown["email_confirmed"];
    blocked: bool = (len(missing) + len(essentials)) > 0 or not confirmed;
    def fields(rows: list[tuple[str, str, str]]) -> list[any] {  # jac:ignore[W1037]
        return [
            <TextField
                key={key}
                field_id={f"verify-{key}"}
                label={label}
                value={typed.get(key, "")}
                error={errors.get(key, "")}
                hint={hint}
                on_value={lambda (v: str) { put(key, v); }}
            /> for (key, label, hint) in rows
        ];
    }
    def drops(rows: list[tuple[str, str]]) -> list[any] {  # jac:ignore[W1037]
        return [
            <div key={item} className="flex flex-col gap-1">
                <PdfDrop
                    field_id={f"verify-file-{item}"}
                    label={label}
                    chosen={"Uploaded" if item in files else ""}
                    busy={busy == item}
                    disabled={not open or busy != ""}
                    on_file={lambda (f: any) { upload(item, f); }}  # jac:ignore[W1037]
                    hint="A photo or a PDF, up to 10 MB."
                    images={True}
                />
                {errors.get(item, "")
                    and <FieldError
                        field_id={f"verify-file-{item}"}
                        error={errors[item]}
                    />}
            </div> for (item, label) in rows
        ];
    }
    return
        <div data-testid="verification" className="flex max-w-2xl flex-col gap-6">
            <p className="text-sm text-muted-foreground">
                Before your cinema goes public, AfriCinemas checks who runs it. Fill this in once; it takes about ten minutes with your ID and your business's certificates to hand.
            </p>
            <Status view={shown}/>
            {shown["status"] == "approved" and <ShareLink slug={slug}/>}
            <Notice/>
            <form
                className="flex flex-col gap-6"
                onSubmit={submit_with(lambda { save(); })}
                data-testid="verification-form"
            >
                <fieldset
                    disabled={not open}
                    className="flex flex-col gap-4 rounded-lg border bg-card p-4"
                >
                    <legend className="px-1 font-semibold">About you</legend>
                    {fields(ABOUT_YOU)}
                </fieldset>
                <fieldset
                    disabled={not open}
                    className="flex flex-col gap-4 rounded-lg border bg-card p-4"
                >
                    <legend className="px-1 font-semibold">Your business</legend>
                    {fields(BUSINESS[:2])}
                    <div className="flex flex-col gap-1.5">
                        <Label htmlFor="verify-business_type">Type of business</Label>
                        <select
                            id="verify-business_type"
                            value={typed.get("business_type", "")}
                            aria-invalid={"true"
                                if errors.get("business_type", "")
                                else "false"}
                            onChange={picked_type}
                            className="min-h-11 rounded-md border bg-background px-3"
                        >
                            <option value="">Choose…</option>
                            {[
                                <option key={t[0]} value={t[0]}>{t[1]}</option>
                                for t in TYPES
                            ]}
                        </select>
                        {errors.get("business_type", "")
                            and <FieldError
                                field_id="verify-business_type"
                                error={errors["business_type"]}
                            />}
                    </div>
                    {fields(BUSINESS[2:])}
                    <div className="flex flex-col gap-1.5">
                        <Label htmlFor="verify-permit_expiry">
                            County permit expires on
                        </Label>
                        <Input
                            id="verify-permit_expiry"
                            type="date"
                            value={typed.get("permit_expiry", "")}
                            aria-invalid={"true"
                                if errors.get("permit_expiry", "")
                                else "false"}
                            onChange={picked_expiry}
                            className="min-h-11 w-fit"
                        />
                        {errors.get("permit_expiry", "")
                            and <FieldError
                                field_id="verify-permit_expiry"
                                error={errors["permit_expiry"]}
                            />}
                    </div>
                </fieldset>
                {open
                    and <Button
                        type="submit"
                        className="min-h-11 w-fit px-5"
                        disabled={busy != ""}
                    >
                        {busy == "save" and <Spinner aria-hidden="true"/>}Save details
                    </Button>}
            </form>
            <section
                aria-labelledby="verify-id-files"
                className="flex flex-col gap-4 rounded-lg border bg-card p-4"
            >
                <h3 id="verify-id-files" className="font-semibold">Your ID</h3>
                <p className="text-sm text-muted-foreground">
                    Your national ID or passport. On a phone, you can take the photos now.
                </p>
                {drops(ID_FILES)}
            </section>
            <section
                aria-labelledby="verify-business-files"
                className="flex flex-col gap-4 rounded-lg border bg-card p-4"
            >
                <h3 id="verify-business-files" className="font-semibold">
                    Your business's documents
                </h3>
                {drops(BUSINESS_FILES)}
            </section>
            {open
                and <section
                    aria-labelledby="verify-submit"
                    className="flex flex-col gap-3 rounded-lg border bg-card p-4"
                    data-testid="verification-submit"
                >
                    <h3 id="verify-submit" className="font-semibold">
                        Before you submit
                    </h3>
                    {not blocked
                        and <p className="text-sm">
                            Everything's here. Send it to AfriCinemas to check.
                        </p>}
                    {not confirmed
                        and <div
                            className="flex flex-wrap items-center gap-2 text-sm"
                            data-testid="verification-email"
                        >
                            <span>
                                Confirm your email, with the link we emailed you when you signed up.
                            </span>
                            <Button
                                type="button"
                                variant="outline"
                                className="min-h-11 px-4"
                                disabled={busy != ""}
                                onClick={lambda { resend(); }}
                            >
                                {busy == "resend"
                                    and <Spinner aria-hidden="true"/>}Send me a new link
                            </Button>
                        </div>}
                    {len(missing) > 0
                        and <ul
                            className="flex list-disc flex-col gap-1 pl-5 text-sm"
                            data-testid="verification-missing"
                        >
                            {[
                                <li key={f"{m['field']}-{i}"}>{m["message"]}</li>
                                for (i, m) in enumerate(missing)
                            ]}
                        </ul>}
                    {len(essentials) > 0
                        and <ul
                            className="flex flex-col gap-1 text-sm"
                            data-testid="verification-essentials"
                        >
                            {[
                                <li key={f"{e['field']}-{i}"}>
                                    <AppLink
                                        to={section_path(
                                            slug, ESSENTIAL_SECTIONS.get(e["field"], "")
                                        )}
                                        className="inline-flex min-h-11 items-center underline underline-offset-4"
                                    >
                                        {e["message"]}
                                    </AppLink>
                                </li> for (i, e) in enumerate(essentials)
                            ]}
                        </ul>}
                    {failed
                        and <Alert variant="destructive" role="alert">
                            <AlertDescription>{failed}</AlertDescription>
                        </Alert>}
                    <Button
                        type="button"
                        className="min-h-11 w-fit px-5"
                        disabled={busy != "" or blocked}
                        data-testid="submit-verification"
                        onClick={lambda { submit(); }}
                    >
                        {busy == "submit"
                            and <Spinner aria-hidden="true"/>}Submit for review
                    </Button>
                </section>}
            <p
                role="status"
                aria-live="polite"
                className="text-sm empty:hidden"
                data-testid="verification-saved"
            >
                {message}
            </p>
        </div>;
}
