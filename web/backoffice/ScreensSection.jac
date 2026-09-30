"""`/app/:slug/screens`: each venue's screens (P3.3, P3.7a).

Everyone who reads seat plans sees the screens, grouped by venue, and opens their seat
layouts. Staff who configure venues also add ("Add screen" opens the name field),
rename and delete screens here; venues themselves are managed on the Venues page.
Deleting asks first; the server's refusals (a name already taken, a screen with
screenings) are shown next to what they concern.
"""

import from react { useState, useEffect }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { ArrowRight01Icon }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.catalog.venue_api {
    list_venues,  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)
    create_auditorium,  # jac:ignore[W2037]
    rename_auditorium,  # jac:ignore[W2037]
    delete_auditorium  # jac:ignore[W2037]
}
import from ..shell.AppLink { AppLink }
import from .form_parts {
    TextField,
    FieldError,
    ConfirmDelete,
    field_for,
    error_id,
    on_input,
    submit_with
}
import from .VenuesSection { place_of }

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
    [new_screens, set_new_screens] = useState({});
    [renaming, set_renaming] = useState("");
    [rename_text, set_rename_text] = useState("");
    [confirming, set_confirming] = useState(None);
    # The add form stays folded behind its button until asked for.
    [adding_screen, set_adding_screen] = useState("");
    manage = "venues.configure" in permissions;

    async def load {
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await list_venues(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("list_venues failed", e);
            set_failed("We couldn't load your screens. Refresh the page to try again.");
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
        # the field it concerns, else at fields["*"] (the screen it's about), else at
        # the top of the page.
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
            set_adding_screen("");
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
        await run(
            lambda -> any { return delete_auditorium(slug, target["id"]); },  # jac:ignore[W1037,W2037]
            {"*": f"problem-screen-{target['id']}"},
            f"Deleted {target['name']}."
        );
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

    def cancel_new_screen {
        set_adding_screen("");
        only_error("", "");
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
                        auto_focus={True}
                    />
                    <div className="flex flex-wrap gap-3">
                        <Button type="submit" className="min-h-11 px-5" disabled={busy}>
                            Save name
                        </Button>
                        <Button
                            type="button"
                            variant="ghost"
                            className="min-h-11 px-5"
                            onClick={lambda {
                                set_renaming("");
                                only_error("", "");
                            }}
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
                                    {"id": sid, "name": a["name"]}
                                ); }}
                            >
                                Delete
                            </Button>
                        </div>}
                </div>
                {asking is not None
                    and asking["id"] == sid
                    and <ConfirmDelete
                        question={f"Delete {asking['name']}?"}
                        detail="Its seat layouts are deleted with it. Screens with screenings can't be deleted."
                        confirm_label="Delete screen"
                        on_confirm={confirm_delete}
                        on_cancel={lambda { set_confirming(None); }}
                        busy={busy}
                    />}
                {field_errors[f"problem-screen-{sid}"]
                    and <FieldError
                        field_id={f"problem-screen-{sid}"}
                        error={field_errors[f"problem-screen-{sid}"]}
                    />}
            </div>;
    }

    def ScreenAdder(v: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
        # "Add screen" for this venue, or its name field once asked for.
        vid: str = v["venue_id"];
        field_id = f"new-screen-{vid}";
        problem = field_errors[field_id] or "";
        if adding_screen != vid {
            return
                <Button
                    variant="outline"
                    className="min-h-11 w-fit px-5"
                    aria-label={f"Add screen at {v['name']}"}
                    onClick={lambda {
                        set_adding_screen(vid);
                        only_error("", "");
                    }}
                >
                    Add screen
                </Button>;
        }
        return
            <form
                className="flex flex-col gap-1.5"
                onSubmit={submit_with(lambda { add_screen(vid); })}
            >
                <Label htmlFor={field_id}>New screen at {v["name"]}</Label>
                <div className="flex flex-wrap gap-2">
                    <Input
                        id={field_id}
                        value={typed_names[vid] or ""}
                        placeholder="e.g. Screen 2"
                        autoFocus={True}
                        aria-invalid={"true" if problem else "false"}
                        aria-describedby={error_id(field_id) if problem else None}
                        onChange={on_input(
                            lambda (text: str) { type_new_screen(vid, text); }
                        )}
                        className="min-h-11 min-w-0 flex-1 basis-48"
                    />
                    <Button
                        type="submit"
                        className="min-h-11 px-5"
                        disabled={busy or not (typed_names[vid] or "").strip()}
                    >
                        Create screen
                    </Button>
                    <Button
                        type="button"
                        variant="ghost"
                        className="min-h-11 px-5"
                        onClick={cancel_new_screen}
                    >
                        Cancel
                    </Button>
                </div>
                {problem and <FieldError field_id={field_id} error={problem}/>}
            </form>;
    }

    return
        <div className="flex flex-col gap-8" data-testid="screens-page">
            <p role="status" aria-live="polite" className="text-sm empty:hidden">
                {message}
            </p>
            {len(listed) == 0
                and <div className="flex flex-col gap-3 rounded-lg border bg-card p-6">
                    <div className="flex flex-col gap-1">
                        <h2 className="text-base font-semibold">No venues yet</h2>
                        <p className="text-sm text-muted-foreground">
                            {"Screens belong to a venue. Add your first venue, then come back to add its screens."
                                if manage
                                else "Once your cinema's venues and screens are set up, they'll appear here."}
                        </p>
                    </div>
                    {manage
                        and <Button asChild={True} className="min-h-11 w-fit px-5">
                            <AppLink to={f"/app/{slug}/venues"}>Go to Venues</AppLink>
                        </Button>}
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
                            <div className="flex flex-col">
                                <h2
                                    id={f"venue-{v['venue_id']}"}
                                    className="text-lg font-semibold"
                                >
                                    {v["name"]}
                                </h2>
                                {place_of(v)
                                    and <p className="text-sm text-muted-foreground">
                                        {place_of(v)}
                                    </p>}
                            </div>
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
                            {manage and ScreenAdder(v)}
                        </section> for v in listed
                    ]}
                </div>}
        </div>;
}
