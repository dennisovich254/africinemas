"""`/app/:slug/screens`: the cinema's venues and their screens (P3.3, P3.7a).

Everyone who reads seat plans sees each venue's screens and opens their seat layouts.
Staff who configure venues also add, edit and delete venues and screens here. Deleting
asks first; the server's refusals (a name already taken, a venue that still has
screens, a screen with screenings) are shown next to what they concern.
"""

import from react { useState, useEffect }
import from ..shell.AppLink { AppLink }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { ArrowRight01Icon }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.catalog.venue_api {
    list_venues,  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)
    create_venue,  # jac:ignore[W2037]
    update_venue,  # jac:ignore[W2037]
    delete_venue,  # jac:ignore[W2037]
    create_auditorium,  # jac:ignore[W2037]
    rename_auditorium,  # jac:ignore[W2037]
    delete_auditorium  # jac:ignore[W2037]
}
import from .form_parts {
    TextField,
    FieldError,
    ConfirmDelete,
    field_for,
    error_id,
    on_input,
    submit_with
}

def:pub screen_path(slug: str, auditorium_id: str) -> str {
    return f"/app/{slug}/screens/{auditorium_id}";
}

def screens_of(venue: dict[str, any]) -> list[dict[str, any]] {  # jac:ignore[W1037]
    return venue["auditoriums"];
}

def layout_status(screen: dict[str, any]) -> str {  # jac:ignore[W1037]
    # This screen's own seat layout, e.g. "Published · version 1 · 62 seats".
    info: dict[str, any] = screen["layout"];  # jac:ignore[W1037]
    count = info["seat_count"];
    seats = "1 seat" if count == 1 else f"{count} seats";
    if info["draft_version"] {
        text = f"Draft · version {info['draft_version']} · {seats}";
        if info["published_version"] {
            text += f" · version {info['published_version']} published";
        }
        return text;
    }
    if info["published_version"] {
        return f"Published · version {info['published_version']} · {seats}";
    }
    return "No layout yet";
}

def ScreenLink(slug: str, screen: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
    return
        <AppLink
            to={screen_path(slug, screen["auditorium_id"])}
            className="flex min-h-14 min-w-0 flex-1 items-center gap-3 rounded-lg border bg-card px-4 py-3 transition-colors hover:bg-muted"
        >
            <span className="flex min-w-0 flex-1 flex-col">
                <span className="truncate font-medium" data-testid="screen-name">
                    {screen["name"]}
                </span>
                <span
                    className="text-sm text-muted-foreground"
                    data-testid="screen-status"
                >
                    {layout_status(screen)}
                </span>
            </span>
            <HugeiconsIcon
                icon={ArrowRight01Icon}
                strokeWidth={2}
                aria-hidden="true"
                className="shrink-0 text-muted-foreground"
            />
        </AppLink>;
}

def:pub ScreensSection(slug: str, permissions: list[str]) -> JsxElement {
    [venues, set_venues] = useState(None);
    [failed, set_failed] = useState("");
    [busy, set_busy] = useState(False);
    [errors, set_errors] = useState({});
    [message, set_message] = useState("");
    [new_venue, set_new_venue] = useState({"name": "", "city": "", "address": ""});
    [editing, set_editing] = useState("");
    [venue_form, set_venue_form] = useState({"name": "", "city": "", "address": ""});
    [new_screens, set_new_screens] = useState({});
    [renaming, set_renaming] = useState("");
    [rename_text, set_rename_text] = useState("");
    [confirming, set_confirming] = useState(None);
    manage = "venues.configure" in permissions;

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
    venue_values: dict[str, str] = venue_form;
    new_values: dict[str, str] = new_venue;
    typed_names: dict[str, str] = new_screens;

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
        # the field it concerns, else at fields["*"] (the item it's about), else at the
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
            set_new_venue({"name": "", "city": "", "address": ""});
        }
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

    async def add_screen(venue_id: str) {
        typed: dict[str, str] = new_screens;
        name = typed[venue_id] or "";
        ok = await run(
            lambda -> any { return create_auditorium(slug, venue_id, name); },  # jac:ignore[W1037,W2037]
            {"name": f"new-screen-{venue_id}"},
            f"Added {name}."
        );
        if ok {
            cleared: dict[str, str] = {};
            for k in typed {
                cleared[k] = typed[k];
            }
            cleared[venue_id] = "";
            set_new_screens(cleared);
        }
    }

    async def save_screen_name(screen_id: str) {
        name: str = rename_text;
        ok = await run(
            lambda -> any { return rename_auditorium(slug, screen_id, name); },  # jac:ignore[W1037,W2037]
            {"name": f"screen-name-{screen_id}"},
            f"Renamed to {name}."
        );
        if ok {
            set_renaming("");
        }
    }

    async def confirm_delete {
        target: dict[str, str] = confirming;
        set_confirming(None);
        if target["kind"] == "venue" {
            await run(
                lambda -> any { return delete_venue(slug, target["id"]); },  # jac:ignore[W1037,W2037]
                {"*": f"problem-venue-{target['id']}"},
                f"Deleted {target['name']}."
            );
        } else {
            await run(
                lambda -> any { return delete_auditorium(slug, target["id"]); },  # jac:ignore[W1037,W2037]
                {"*": f"problem-screen-{target['id']}"},
                f"Deleted {target['name']}."
            );
        }
    }

    def edit_new_venue(key: str, value: str) {
        form: dict[str, str] = {};
        was: dict[str, str] = new_venue;
        for k in was {
            form[k] = was[k];
        }
        form[key] = value;
        set_new_venue(form);
    }

    def edit_venue_form(key: str, value: str) {
        form: dict[str, str] = {};
        was: dict[str, str] = venue_form;
        for k in was {
            form[k] = was[k];
        }
        form[key] = value;
        set_venue_form(form);
    }

    def type_new_screen(venue_id: str, value: str) {
        typed: dict[str, str] = {};
        was: dict[str, str] = new_screens;
        for k in was {
            typed[k] = was[k];
        }
        typed[venue_id] = value;
        set_new_screens(typed);
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
                Loading screens…
            </p>;
    }
    listed: list[dict[str, any]] = venues;  # jac:ignore[W1037]
    asking: dict[str, str] | None = confirming;

    def confirm_box(kind: str, item_id: str) -> any {  # jac:ignore[W1037]
        if asking is None or asking["kind"] != kind or asking["id"] != item_id {
            return None;
        }
        detail = (
            "Its screens must be deleted first."
                if kind == "venue"
                else "Its seat layouts are deleted with it. Screens with screenings can't be deleted."
        );
        return
            <ConfirmDelete
                question={f"Delete {asking['name']}?"}
                detail={detail}
                confirm_label={"Delete venue" if kind == "venue" else "Delete screen"}
                on_confirm={confirm_delete}
                on_cancel={lambda { set_confirming(None); }}
                busy={busy}
            />;
    }

    def VenueHeader(v: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
        vid: str = v["venue_id"];
        if editing == vid {
            return
                <form
                    className="grid gap-3 rounded-lg border p-4 sm:grid-cols-2"
                    onSubmit={submit_with(lambda { save_venue(vid); })}
                >
                    <h2
                        id={f"venue-{vid}"}
                        className="text-lg font-semibold sm:col-span-2"
                    >
                        Edit {v["name"]}
                    </h2>
                    <TextField
                        field_id={f"venue-name-{vid}"}
                        label="Venue name"
                        value={venue_values["name"]}
                        error={field_errors[f"venue-name-{vid}"] or ""}
                        on_value={lambda (text: str) { edit_venue_form("name", text); }}
                    />
                    <TextField
                        field_id={f"venue-city-{vid}"}
                        label="City"
                        value={venue_values["city"]}
                        error={field_errors[f"venue-city-{vid}"] or ""}
                        on_value={lambda (text: str) { edit_venue_form("city", text); }}
                    />
                    <div className="sm:col-span-2">
                        <TextField
                            field_id={f"venue-address-{vid}"}
                            label="Address"
                            value={venue_values["address"]}
                            error={field_errors[f"venue-address-{vid}"] or ""}
                            on_value={lambda (text: str) { edit_venue_form(
                                "address", text
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
                            onClick={lambda { set_editing(""); }}
                        >
                            Cancel
                        </Button>
                    </div>
                </form>;
        }
        return
            <div className="flex flex-wrap items-center justify-between gap-3">
                <div className="flex min-w-0 flex-col">
                    <h2 id={f"venue-{vid}"} className="text-lg font-semibold">
                        {v["name"]}
                    </h2>
                    {(v["city"] or v["address"])
                        and <p className="text-sm text-muted-foreground">
                            {", ".join(
                                [
                                    x
                                    for x in [v["address"], v["city"]]
                                    if x
                                ]
                            )}
                        </p>}
                </div>
                {manage
                    and <div className="flex gap-2">
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
                            onClick={lambda { set_confirming(
                                {"kind": "venue", "id": vid, "name": v["name"]}
                            ); }}
                        >
                            Delete
                        </Button>
                    </div>}
            </div>;
    }

    def ScreenRow(a: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
        sid: str = a["auditorium_id"];
        if renaming == sid {
            return
                <form
                    className="flex flex-col gap-3 rounded-lg border p-3"
                    onSubmit={submit_with(lambda { save_screen_name(sid); })}
                >
                    <TextField
                        field_id={f"screen-name-{sid}"}
                        label={f"New name for {a['name']}"}
                        value={rename_text}
                        error={field_errors[f"screen-name-{sid}"] or ""}
                        on_value={lambda (text: str) { set_rename_text(text); }}
                    />
                    <div className="flex flex-wrap gap-3">
                        <Button type="submit" className="min-h-11 px-5" disabled={busy}>
                            Save name
                        </Button>
                        <Button
                            type="button"
                            variant="ghost"
                            className="min-h-11 px-5"
                            onClick={lambda { set_renaming(""); }}
                        >
                            Cancel
                        </Button>
                    </div>
                </form>;
        }
        return
            <div className="flex flex-col gap-2">
                <div className="flex items-stretch gap-2">
                    <ScreenLink slug={slug} screen={a}/>
                    {manage
                        and <div
                            className="flex shrink-0 flex-col gap-1 sm:flex-row sm:items-center"
                        >
                            <Button
                                variant="ghost"
                                className="min-h-11 px-3"
                                aria-label={f"Rename {a['name']}"}
                                onClick={lambda {
                                    set_renaming(sid);
                                    set_rename_text(a["name"]);
                                    set_confirming(None);
                                    only_error("", "");
                                }}
                            >
                                Rename
                            </Button>
                            <Button
                                variant="ghost"
                                className="min-h-11 px-3"
                                aria-label={f"Delete {a['name']}"}
                                onClick={lambda { set_confirming(
                                    {"kind": "screen", "id": sid, "name": a["name"]}
                                ); }}
                            >
                                Delete
                            </Button>
                        </div>}
                </div>
                {confirm_box("screen", sid)}
                {field_errors[f"problem-screen-{sid}"]
                    and <FieldError
                        field_id={f"problem-screen-{sid}"}
                        error={field_errors[f"problem-screen-{sid}"]}
                    />}
            </div>;
    }

    add_venue_form = <form
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
            on_value={lambda (text: str) { edit_new_venue("name", text); }}
        />
        <TextField
            field_id="new-venue-city"
            label="City"
            value={new_values["city"]}
            error={field_errors["new-venue-city"] or ""}
            on_value={lambda (text: str) { edit_new_venue("city", text); }}
        />
        <div className="sm:col-span-2">
            <TextField
                field_id="new-venue-address"
                label="Address (optional)"
                value={new_values["address"]}
                error={field_errors["new-venue-address"] or ""}
                on_value={lambda (text: str) { edit_new_venue("address", text); }}
            />
        </div>
        <div className="sm:col-span-2">
            <Button
                type="submit"
                className="min-h-11 px-5"
                disabled={busy or not new_values["name"].strip()}
            >
                Add venue
            </Button>
        </div>
    </form>;

    return
        <div className="flex flex-col gap-8" data-testid="screens-page">
            <p role="status" aria-live="polite" className="text-sm">{message}</p>
            {len(listed) == 0
                and <div className="flex flex-col gap-1 rounded-lg border bg-card p-6">
                    <h2 className="text-base font-semibold">No venues yet</h2>
                    <p className="text-sm text-muted-foreground">
                        {"Add your first venue below, then its screens. You'll design each screen's seat layout here."
                            if manage
                            else "Once your cinema's venues and screens are set up, they'll appear here."}
                    </p>
                </div>}
            {len(listed) > 0
                and <div className="flex flex-col gap-8" data-testid="screens-list">
                    {[
                        <section
                            key={v["venue_id"]}
                            data-testid="venue"
                            aria-labelledby={f"venue-{v['venue_id']}"}
                            className="flex flex-col gap-3"
                        >
                            {VenueHeader(v)}
                            {confirm_box("venue", v["venue_id"])}
                            {field_errors[f"problem-venue-{v['venue_id']}"]
                                and <FieldError
                                    field_id={f"problem-venue-{v['venue_id']}"}
                                    error={field_errors[
                                        f"problem-venue-{v['venue_id']}"
                                    ]}
                                />}
                            {len(screens_of(v)) == 0
                                and <p className="text-sm text-muted-foreground">
                                    No screens at this venue yet.
                                </p>}
                            <ul className="grid gap-3 lg:grid-cols-2">
                                {[
                                    <li key={a["auditorium_id"]}>{ScreenRow(a)}</li>
                                    for a in screens_of(v)
                                ]}
                            </ul>
                            {manage
                                and <form
                                    className="flex flex-col gap-1.5"
                                    onSubmit={submit_with(
                                        lambda { add_screen(v["venue_id"]); }
                                    )}
                                >
                                    <Label htmlFor={f"new-screen-{v['venue_id']}"}>
                                        New screen at {v["name"]}
                                    </Label>
                                    <div className="flex flex-wrap gap-2">
                                        <Input
                                            id={f"new-screen-{v['venue_id']}"}
                                            value={typed_names[v["venue_id"]] or ""}
                                            placeholder="e.g. Screen 2"
                                            aria-invalid={"true"
                                                if field_errors[
                                                    f"new-screen-{v['venue_id']}"
                                                ]
                                                else "false"}
                                            aria-describedby={error_id(
                                                f"new-screen-{v['venue_id']}"
                                            )
                                                if field_errors[
                                                    f"new-screen-{v['venue_id']}"
                                                ]
                                                else None}
                                            onChange={on_input(
                                                lambda (text: str) { type_new_screen(
                                                    v["venue_id"], text
                                                ); }
                                            )}
                                            className="min-h-11 min-w-0 flex-1 basis-48"
                                        />
                                        <Button
                                            type="submit"
                                            variant="outline"
                                            className="min-h-11 px-5"
                                            disabled={busy
                                                or not (
                                                    typed_names[v["venue_id"]] or ""
                                                ).strip()}
                                        >
                                            Add screen
                                        </Button>
                                    </div>
                                    {field_errors[f"new-screen-{v['venue_id']}"]
                                        and <FieldError
                                            field_id={f"new-screen-{v['venue_id']}"}
                                            error={field_errors[
                                                f"new-screen-{v['venue_id']}"
                                            ]}
                                        />}
                                </form>}
                        </section> for v in listed
                    ]}
                </div>}
            {manage and add_venue_form}
        </div>;
}
