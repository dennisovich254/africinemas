"""Settings -> Website information (P14.3a): what every page of the cinema's storefront shows.

The business name and address, how to reach the cinema (phone, email, WhatsApp,
support hours), its social media accounts, directions and parking, and booking notes
(what each ticket type means, how to pay), and whether it sends offers (P14.3c). For staff who change the cinema's settings;
the server checks every field and reports every problem at once, each shown beside its
field (core/catalog/site_info.jac). Saved, it shows in the strip under every storefront
page, whatever the design. Each group is a tab (owner, 2026-10-29) of the one form:
Save saves them all, a tab counts its problems, and a refused save opens the first tab
with one.
"""

import from react { useState, useEffect }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.button { Button }
import from ...components.ui.spinner { Spinner }
import from core.catalog.site_info {
    site_info,  # jac:ignore[W2037] authenticated endpoint
    save_site_info  # jac:ignore[W2037]
}
import from ..shell.Tabs { Tabs }
import from .form_parts { TextField, submit_with }
# Not {**info, key: value}: in client code that sets a key named "key" (JI-055).
import from .snack_view { with_field }

glob TEXT_FIELDS: list[tuple[str, str, str, bool]] = [
         (
             "business_name",
             "Registered business name",
             "As on your business registration.",
             False
         ),
         (
             "address",
             "Physical address",
             "Where the cinema is: building, street, town.",
             False
         )
     ],
     CONTACT_FIELDS: list[tuple[str, str, str, bool]] = [
         ("phone", "Support phone", "A Kenyan number, like 0712 345 678.", False),
         ("email", "Support email", "", False),
         (
             "whatsapp",
             "WhatsApp number",
             "Visitors get a WhatsApp link to this number.",
             False
         ),
         ("support_hours", "Support hours", "Like: Every day, 9am to 10pm.", False)
     ],
     TABS: list[tuple[str, str]] = [
         ("business", "Your business"),
         ("contact", "Contact"),
         ("social", "Social media"),
         ("visit", "Getting here"),
         ("notes", "Booking notes")
     ],
     VISIT_FIELDS: list[tuple[str, str, str, bool]] = [
         (
             "directions",
             "Directions",
             "How to find you: the floor, the entrance, a landmark.",
             True
         ),
         ("parking", "Parking", "Where to park, and what it costs.", False)
     ],
     NETWORKS: list[tuple[str, str]] = [
         ("facebook", "Facebook"),
         ("instagram", "Instagram"),
         ("x", "X"),
         ("tiktok", "TikTok"),
         ("youtube", "YouTube")
     ],
     NOTES_MAX: int = 10;

def tab_of(field: str) -> str {
    # Which tab a field's problem is on.
    if field.startswith("socials.") {
        return "social";
    }
    if field.startswith("ticket_notes.") or field == "payment_note" {
        return "notes";
    }
    if field in [row[0] for row in CONTACT_FIELDS] or field == "sends_offers" {
        return "contact";
    }
    if field in [row[0] for row in VISIT_FIELDS] {
        return "visit";
    }
    return "business";
}

def:pub SiteInfoSection(slug: str, shift_open: bool = True) -> JsxElement {
    [info, set_info] = useState(None);
    [socials, set_socials] = useState({});
    [notes, set_notes] = useState([]);
    [problems, set_problems] = useState({});
    [failed, set_failed] = useState("");
    [busy, set_busy] = useState(False);
    [saved, set_saved] = useState(False);
    [tab, set_tab] = useState("business");

    def show(loaded: dict[str, any]) {  # jac:ignore[W1037]
        set_info(loaded);
        set_socials(loaded["socials"] or {});
        set_notes(loaded["ticket_notes"] or []);
    }
    async def load {
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await site_info(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("site_info failed", e);
        }
        if answer is None {
            set_failed("We couldn't load this. Refresh the page to try again.");
        } elif not answer["ok"] {
            set_failed(answer["error"]["message"]);
        } else {
            set_failed("");
            show(answer["info"]);
        }
    }
    def start {
        load();
    }
    useEffect(start, [slug, shift_open]);

    def put(field: str, value: any) {  # jac:ignore[W1037]
        set_saved(False);
        set_info(with_field(info, field, value));
    }
    def put_social(network: str, value: str) {
        set_saved(False);
        set_socials(with_field(socials, network, value));
    }
    def put_note(index: int, key: str, value: str) {
        set_saved(False);
        set_notes(
            [
                with_field(n, key, value) if i == index else n
                for (i, n) in enumerate(notes)
            ]
        );
    }
    def add_note {
        rows: list[dict[str, str]] = notes;
        set_notes(rows + [{"name": "", "note": ""}]);
    }
    def drop_note(index: int) {
        set_notes(
            [
                n
                for (i, n) in enumerate(notes)
                if i != index
            ]
        );
    }

    async def save {
        set_busy(True);
        set_saved(False);
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await save_site_info(
                slug, {** info, "socials": socials, "ticket_notes": notes}
            );  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("save_site_info failed", e);
        }
        set_busy(False);
        if answer is None {
            set_failed(
                "We couldn't reach AfriCinemas. Check your connection and try again."
            );
            return;
        }
        if not answer["ok"] {
            found: dict[str, str] = {};
            for p in (answer["error"]["problems"] or []) {
                found[p["field"]] = p["message"];
            }
            set_problems(found);
            set_failed(answer["error"]["message"]);
            marked: list[str] = Object.keys(found);  # jac:ignore[W2001]
            first = [
                row[0]
                for row in TABS
                if len(
                    [
                        f
                        for f in marked
                        if tab_of(f) == row[0]
                    ]
                )
                    > 0
            ];
            if len(first) > 0 {
                set_tab(first[0]);
            }
            return;
        }
        set_problems({});
        set_failed("");
        show(answer["info"]);
        set_saved(True);
    }

    if info is None {
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
    shown: dict[str, any] = info;  # jac:ignore[W1037]
    errors: dict[str, str] = problems;
    networks: dict[str, str] = socials;
    def wrong(key: str) -> str {
        marked: list[str] = Object.keys(errors);  # jac:ignore[W2001]
        n = len(
            [
                f
                for f in marked
                if tab_of(f) == key
            ]
        );
        return str(n) if n > 0 else "";
    }
    def fields(rows: list[tuple[str, str, str, bool]]) -> list[any] {  # jac:ignore[W1037]
        return [
            <TextField
                key={key}
                field_id={f"info-{key}"}
                label={label}
                value={shown[key] or ""}
                error={errors.get(key, "")}
                hint={hint}
                multiline={multiline}
                on_value={lambda (v: str) { put(key, v); }}
            /> for (key, label, hint, multiline) in rows
        ];
    }
    return
        <form
            data-testid="site-info"
            className="flex max-w-2xl flex-col gap-6"
            onSubmit={submit_with(lambda { save(); })}
        >
            <p className="text-sm text-muted-foreground">
                Shown on every page of your storefront, whatever its design, so visitors know who you are and how to reach you.
            </p>
            <Tabs
                label="Website information"
                tabs={[
                    {"key": key, "label": label, "count": wrong(key)}
                    for (key, label) in TABS
                ]}
                current={tab}
                on_pick={set_tab}
                testid="site-info-tab"
            />
            {tab == "business"
                and <fieldset
                    className="flex flex-col gap-4 rounded-lg border bg-card p-4"
                >
                    <legend className="px-1 font-semibold">Your business</legend>
                    {fields(TEXT_FIELDS)}
                </fieldset>}
            {tab == "contact"
                and <fieldset
                    className="flex flex-col gap-4 rounded-lg border bg-card p-4"
                >
                    <legend className="px-1 font-semibold">Contact</legend>
                    {fields(CONTACT_FIELDS)}
                    <label
                        className="flex min-h-11 cursor-pointer items-center gap-3 text-sm"
                    >
                        <input
                            type="checkbox"
                            id="info-sends_offers"
                            className="size-5"
                            checked={bool(shown["sends_offers"])}
                            onChange={lambda { put(
                                "sends_offers", not shown["sends_offers"]
                            ); }}
                        />
                        We send offers to customers who ask for them. Checkout and sign-up then offer a box to ask, never ticked for them.
                    </label>
                </fieldset>}
            {tab == "social"
                and <fieldset
                    className="flex flex-col gap-4 rounded-lg border bg-card p-4"
                >
                    <legend className="px-1 font-semibold">Social media</legend>
                    <p className="text-sm text-muted-foreground">
                        The account's name only, like anga_cinemas. We make the links.
                    </p>
                    {[
                        <TextField
                            key={network}
                            field_id={f"info-social-{network}"}
                            label={label}
                            value={networks.get(network, "")}
                            error={errors.get(f"socials.{network}", "")}
                            on_value={lambda (v: str) { put_social(network, v); }}
                        /> for (network, label) in NETWORKS
                    ]}
                </fieldset>}
            {tab == "visit"
                and <fieldset
                    className="flex flex-col gap-4 rounded-lg border bg-card p-4"
                >
                    <legend className="px-1 font-semibold">Getting here</legend>
                    {fields(VISIT_FIELDS)}
                </fieldset>}
            {tab == "notes"
                and <fieldset
                    className="flex flex-col gap-4 rounded-lg border bg-card p-4"
                >
                    <legend className="px-1 font-semibold">Booking notes</legend>
                    <p className="text-sm text-muted-foreground">
                        Shown before visitors choose tickets: what a ticket type means, like Child: under 12, or Student: bring your ID.
                    </p>
                    {[
                        <div
                            key={f"note-{i}"}
                            className="flex flex-col gap-2 rounded-md border p-3"
                            data-testid="ticket-note"
                        >
                            <TextField
                                field_id={f"info-note-{i}-name"}
                                label="Ticket type"
                                value={n["name"]}
                                error={errors.get(f"ticket_notes.{i}.name", "")
                                    or errors.get(f"ticket_notes.{i}", "")}
                                on_value={lambda (v: str) { put_note(i, "name", v); }}
                            />
                            <TextField
                                field_id={f"info-note-{i}-note"}
                                label="What it means"
                                value={n["note"]}
                                error={errors.get(f"ticket_notes.{i}.note", "")}
                                on_value={lambda (v: str) { put_note(i, "note", v); }}
                            />
                            <Button
                                type="button"
                                variant="ghost"
                                className="min-h-11 w-fit px-3"
                                onClick={lambda { drop_note(i); }}
                            >
                                Remove
                            </Button>
                        </div> for (i, n) in enumerate(notes)
                    ]}
                    {len(notes) < NOTES_MAX
                        and <Button
                            type="button"
                            variant="outline"
                            className="min-h-11 w-fit px-4"
                            onClick={add_note}
                            data-testid="add-ticket-note"
                        >
                            Add a note
                        </Button>}
                    <TextField
                        field_id="info-payment_note"
                        label="How to pay"
                        value={shown["payment_note"] or ""}
                        error={errors.get("payment_note", "")}
                        hint="Like: Pay with M-Pesa online, or cash at the box office."
                        on_value={lambda (v: str) { put("payment_note", v); }}
                    />
                </fieldset>}
            {failed
                and <Alert variant="destructive" role="alert">
                    <AlertDescription>{failed}</AlertDescription>
                </Alert>}
            <p
                role="status"
                aria-live="polite"
                className="text-sm empty:hidden"
                data-testid="site-info-saved"
            >
                {"Saved. It's on your storefront now." if saved else ""}
            </p>
            <Button type="submit" className="min-h-11 w-fit px-5" disabled={busy}>
                {busy and <Spinner aria-hidden="true"/>}Save
            </Button>
        </form>;
}
