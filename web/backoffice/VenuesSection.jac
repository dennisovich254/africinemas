"""`/app/:slug/venues`: the cinema's venues (P3.7a), for staff who configure venues.

Each venue shows where it is and how many screens it has, with a link to them on the
Screens page. Venues are added (the form opens from "Add venue"), edited and deleted
here; deleting asks first, and the server's refusals (a name already taken, a venue that
still has screens or staff) are shown next to what they concern.
"""

import from react { useState, useEffect }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.button { Button }
import from ...components.ui.spinner { Spinner }
import from core.catalog.venue_api {
    list_venues,  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)
    create_venue,  # jac:ignore[W2037]
    update_venue,  # jac:ignore[W2037]
    delete_venue  # jac:ignore[W2037]
}
import from ..shell.AppLink { AppLink }
import from .form_parts { TextField, FieldError, ConfirmDelete, field_for, submit_with }

glob BLANK: dict[str, str] = {"name": "", "city": "", "address": ""};

def:pub place_of(venue: dict[str, any]) -> str {  # jac:ignore[W1037]
    # "Sarit Centre, Nairobi", or "" when neither is set.
    return ", ".join(
        [
            x
            for x in [venue["address"], venue["city"]]
            if x
        ]
    );
}

def:pub screen_count(venue: dict[str, any]) -> str {  # jac:ignore[W1037]
    count = len(venue["auditoriums"]);
    if count == 0 {
        return "No screens yet";
    }
    return "1 screen" if count == 1 else f"{count} screens";
}

def:pub VenuesSection(slug: str) -> JsxElement {
    [venues, set_venues] = useState(None);
    [failed, set_failed] = useState("");
    [busy, set_busy] = useState(False);
    [errors, set_errors] = useState({});
    [message, set_message] = useState("");
    [adding, set_adding] = useState(False);
    [new_venue, set_new_venue] = useState(BLANK);
    [editing, set_editing] = useState("");
    [venue_form, set_venue_form] = useState(BLANK);
    [confirming, set_confirming] = useState(None);

    async def load {
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await list_venues(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("list_venues failed", e);
            set_failed("We couldn't load your venues. Refresh the page to try again.");
            return;
        }
        if not answer["ok"] {
            set_failed(answer["error"]["message"]);
            return;
        }
        set_venues(answer["venues"]);
    }

    # A named function, not a one-statement lambda (JI-028).
    def start_loading {
        load();
    }
    useEffect(start_loading, [slug]);

    field_errors: dict[str, str] = errors;
    new_values: dict[str, str] = new_venue;
    edit_values: dict[str, str] = venue_form;

    def only_error(field_id: str, text: str) {
        # Shows `text` under `field_id` and clears every other error.
        shown: dict[str, str] = {};
        if field_id {
            shown[field_id] = text;
        }
        set_errors(shown);
    }

    async def run(call: any, fields: dict[str, str], done: str) -> bool {  # jac:ignore[W1037]
        # Runs a change; on success reloads and announces `done`. A refusal is shown by
        # the field it concerns, else at fields["*"] (the venue it's about), else at the
        # top of the page.
        answer: any = None;  # jac:ignore[W1037]
        set_busy(True);
        set_message("");
        try {
            answer = await call();
        } except Exception as e {
            console.warn("change failed", e);
            set_busy(False);
            only_error("", "");
            set_message("We couldn't save that. Check your connection and try again.");
            return False;
        }
        set_busy(False);
        if not answer["ok"] {
            target = field_for(answer["error"]["code"], fields);
            if not target and "*" in fields {
                target = fields["*"];
            }
            if target {
                only_error(target, answer["error"]["message"]);
            } else {
                only_error("", "");
                set_message(answer["error"]["message"]);
            }
            return False;
        }
        only_error("", "");
        set_message(done);
        await load();
        return True;
    }

    def copy_with(form: dict[str, str], key: str, value: str) -> dict[str, str] {
        changed: dict[str, str] = {};
        for k in form {
            changed[k] = form[k];
        }
        changed[key] = value;
        return changed;
    }

    async def add_venue {
        form: dict[str, str] = new_venue;
        def send -> any {  # jac:ignore[W1037]
            return create_venue(slug, form["name"], form["city"], form["address"]);  # jac:ignore[W2037]
        }
        ok = await run(
            send,
            {
                "name": "new-venue-name",
                "city": "new-venue-city",
                "address": "new-venue-address"
            },
            f"Added {form['name']}."
        );
        if ok {
            set_new_venue(BLANK);
            set_adding(False);
        }
    }

    def cancel_new {
        set_adding(False);
        set_new_venue(BLANK);
        only_error("", "");
    }

    def start_edit(v: dict[str, any]) {  # jac:ignore[W1037]
        set_editing(v["venue_id"]);
        set_venue_form({"name": v["name"], "city": v["city"], "address": v["address"]});
        set_confirming(None);
        only_error("", "");
    }

    async def save_venue(venue_id: str) {
        form: dict[str, str] = venue_form;
        def send -> any {  # jac:ignore[W1037]
            return update_venue(  # jac:ignore[W2037]
                slug, venue_id, form["name"], form["city"], form["address"]
            );
        }
        ok = await run(
            send,
            {
                "name": f"venue-name-{venue_id}",
                "city": f"venue-city-{venue_id}",
                "address": f"venue-address-{venue_id}"
            },
            f"Saved {form['name']}."
        );
        if ok {
            set_editing("");
        }
    }

    async def confirm_delete {
        target: dict[str, str] = confirming;
        set_confirming(None);
        await run(
            lambda -> any { return delete_venue(slug, target["id"]); },  # jac:ignore[W1037,W2037]
            {"*": f"problem-venue-{target['id']}"},
            f"Deleted {target['name']}."
        );
    }

    if failed {
        return
            <Alert variant="destructive">
                <AlertDescription>{failed}</AlertDescription>
            </Alert>;
    }
    if venues is None {
        return
            <p role="status" className="flex items-center gap-2 text-muted-foreground">
                <Spinner aria-hidden="true"/>
                Loading venues…
            </p>;
    }
    listed: list[dict[str, any]] = venues;  # jac:ignore[W1037]
    asking: dict[str, str] | None = confirming;

    def EditForm(v: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
        vid: str = v["venue_id"];
        return
            <form
                className="grid gap-3 sm:grid-cols-2"
                onSubmit={submit_with(lambda { save_venue(vid); })}
            >
                <h2 id={f"venue-{vid}"} className="text-lg font-semibold sm:col-span-2">
                    Edit {v["name"]}
                </h2>
                <TextField
                    field_id={f"venue-name-{vid}"}
                    label="Venue name"
                    value={edit_values["name"]}
                    error={field_errors[f"venue-name-{vid}"] or ""}
                    on_value={lambda (text: str) { set_venue_form(
                        copy_with(edit_values, "name", text)
                    ); }}
                    auto_focus={True}
                />
                <TextField
                    field_id={f"venue-city-{vid}"}
                    label="City"
                    value={edit_values["city"]}
                    error={field_errors[f"venue-city-{vid}"] or ""}
                    on_value={lambda (text: str) { set_venue_form(
                        copy_with(edit_values, "city", text)
                    ); }}
                />
                <div className="sm:col-span-2">
                    <TextField
                        field_id={f"venue-address-{vid}"}
                        label="Address (optional)"
                        value={edit_values["address"]}
                        error={field_errors[f"venue-address-{vid}"] or ""}
                        on_value={lambda (text: str) { set_venue_form(
                            copy_with(edit_values, "address", text)
                        ); }}
                    />
                </div>
                <div className="flex flex-wrap gap-3 sm:col-span-2">
                    <Button type="submit" className="min-h-11 px-5" disabled={busy}>
                        Save venue
                    </Button>
                    <Button
                        type="button"
                        variant="ghost"
                        className="min-h-11 px-5"
                        onClick={lambda {
                            set_editing("");
                            only_error("", "");
                        }}
                    >
                        Cancel
                    </Button>
                </div>
            </form>;
    }

    def VenueCard(v: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
        vid: str = v["venue_id"];
        problem = field_errors[f"problem-venue-{vid}"] or "";
        body: any = None;  # jac:ignore[W1037]
        if editing == vid {
            body = EditForm(v);
        } else {
            body = <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="flex min-w-0 flex-col gap-1">
                    <h2 id={f"venue-{vid}"} className="text-lg font-semibold">
                        {v["name"]}
                    </h2>
                    {place_of(v)
                        and <p className="text-sm text-muted-foreground">
                            {place_of(v)}
                        </p>}
                    <AppLink
                        to={f"/app/{slug}/screens#venue-{vid}"}
                        className="inline-flex min-h-11 w-fit items-center text-sm font-medium underline underline-offset-4"
                    >
                        {screen_count(v)} · Manage screens
                    </AppLink>
                </div>
                <div className="flex gap-2">
                    <Button
                        variant="outline"
                        className="min-h-11 px-4"
                        aria-label={f"Edit {v['name']}"}
                        onClick={lambda { start_edit(v); }}
                    >
                        Edit
                    </Button>
                    <Button
                        variant="outline"
                        className="min-h-11 px-4"
                        aria-label={f"Delete {v['name']}"}
                        onClick={lambda {
                            set_confirming(
                                {"kind": "venue", "id": vid, "name": v["name"]}
                            );
                            set_editing("");
                        }}
                    >
                        Delete
                    </Button>
                </div>
            </div>;
        }
        return
            <li
                key={vid}
                data-testid="venue"
                aria-labelledby={f"venue-{vid}"}
                className="flex flex-col gap-3 rounded-lg border bg-card p-4"
            >
                {body}{asking is not None
                    and asking["id"] == vid
                    and <ConfirmDelete
                        question={f"Delete {asking['name']}?"}
                        detail="A venue can be deleted once it has no screens and no staff limited to it."
                        confirm_label="Delete venue"
                        on_confirm={confirm_delete}
                        on_cancel={lambda { set_confirming(None); }}
                        busy={busy}
                    />}{problem
                    and <FieldError field_id={f"problem-venue-{vid}"} error={problem}/>}
            </li>;
    }

    add_button = <Button
        className="min-h-11 w-fit px-5"
        onClick={lambda {
            set_adding(True);
            set_editing("");
            only_error("", "");
        }}
    >
        Add venue
    </Button>;

    add_form = <form
        data-testid="add-venue"
        className="grid gap-3 rounded-lg border p-4 sm:grid-cols-2"
        onSubmit={submit_with(lambda { add_venue(); })}
    >
        <h2 className="text-lg font-semibold sm:col-span-2">Add a venue</h2>
        <TextField
            field_id="new-venue-name"
            label="Venue name"
            value={new_values["name"]}
            error={field_errors["new-venue-name"] or ""}
            on_value={lambda (text: str) { set_new_venue(
                copy_with(new_values, "name", text)
            ); }}
            auto_focus={True}
        />
        <TextField
            field_id="new-venue-city"
            label="City"
            value={new_values["city"]}
            error={field_errors["new-venue-city"] or ""}
            on_value={lambda (text: str) { set_new_venue(
                copy_with(new_values, "city", text)
            ); }}
        />
        <div className="sm:col-span-2">
            <TextField
                field_id="new-venue-address"
                label="Address (optional)"
                value={new_values["address"]}
                error={field_errors["new-venue-address"] or ""}
                on_value={lambda (text: str) { set_new_venue(
                    copy_with(new_values, "address", text)
                ); }}
            />
        </div>
        <div className="flex flex-wrap gap-3 sm:col-span-2">
            <Button
                type="submit"
                className="min-h-11 px-5"
                disabled={busy or not new_values["name"].strip()}
            >
                Create venue
            </Button>
            <Button
                type="button"
                variant="ghost"
                className="min-h-11 px-5"
                onClick={cancel_new}
            >
                Cancel
            </Button>
        </div>
    </form>;

    return
        <div className="flex flex-col gap-6" data-testid="venues-page">
            <p role="status" aria-live="polite" className="text-sm empty:hidden">
                {message}
            </p>
            {len(listed) == 0
                and not adding
                and <div className="flex flex-col gap-3 rounded-lg border bg-card p-6">
                    <div className="flex flex-col gap-1">
                        <h2 className="text-base font-semibold">No venues yet</h2>
                        <p className="text-sm text-muted-foreground">
                            A venue is one of your cinema's locations. Add your first, then its screens.
                        </p>
                    </div>
                    {add_button}
                </div>}
            {len(listed) > 0
                and <div className="flex flex-wrap items-center justify-between gap-3">
                    <p className="text-sm text-muted-foreground">
                        {"1 venue" if len(listed) == 1 else f"{len(listed)} venues"}
                    </p>
                    {not adding and add_button}
                </div>}
            {adding and add_form}
            {len(listed) > 0
                and <ul className="grid gap-3 lg:grid-cols-2" data-testid="venue-list">
                    {[VenueCard(v) for v in listed]}
                </ul>}
        </div>;
}
