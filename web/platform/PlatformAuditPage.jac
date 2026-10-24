"""The platform console's Audit log section (P13.3): what AfriCinemas' team did.

`/audit`: the platform's own events, newest first, PAGE at a time with Previous and
Next, as the cinema audit log is (web/backoffice/AuditSection.jac). It's narrowed by an
action, a search of who did it or who it was done to, and a cinema (`?cinema=<slug>`,
from a cinema's page), shown as a filter that can be cleared. Each row says when (in
this browser's time zone), who, what, to whom or what, and the result in words.
Refused attempts are there too, by accounts that aren't platform staff as well. For
super admins (platform.audit); the server checks every request. Nobody can change or
delete an event, so the page has no actions.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { useLocation }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.platform.audit_api { platform_audit_log }  # jac:ignore[W2037] authenticated endpoint
import from ..shell.AppLink { AppLink }
import from ..shell.ResponsiveTable { ResponsiveTable }
import from ..storefront.showtimes { day_label, time_label }
import from ..backoffice.SearchSelect { SearchSelect }
import from ..backoffice.form_parts { on_input }

glob PAGE: int = 25,
     SEARCH_PAUSE_MS: int = 300,
     ACTIONS: list[tuple[str, str]] = [
         ("platform.signed_in", "Signed in"),
         ("platform.joined", "Joined the platform"),
         ("platform.staff_invited", "Invited to the platform"),
         ("platform.staff_role_set", "Platform role changed"),
         ("platform.staff_removed", "Removed from the platform"),
         ("platform.cinema_approved", "Approved a cinema"),
         ("platform.verification_approved", "Approved a cinema's verification"),
         ("platform.verification_changes_requested", "Asked a cinema for changes"),
         ("platform.verification_rejected", "Rejected a cinema's verification"),
         ("platform.verification_file_viewed", "Opened a verification document"),
         ("platform.support_replied", "Replied to a help request"),
         ("platform.support_closed", "Closed a help request"),
         ("platform.support_reopened", "Reopened a help request")
     ],
     COLUMNS: list[dict[str, str]] = [
         {"key": "when", "label": "When"},
         {"key": "who", "label": "Who"},
         {"key": "what", "label": "What"},
         {"key": "on", "label": "On"},
         {"key": "result", "label": "Result"}
     ];

def action_label(action: str) -> str {
    for (code, label) in ACTIONS {
        if code == action {
            return label;
        }
    }
    return action;
}

def result_label(result: str) -> str {
    # The result in words (never a colour alone).
    if result == "ok" {
        return "Done";
    }
    if result == "pending" {
        return "Not finished";
    }
    if result == "not_platform" {
        return "Refused: not AfriCinemas staff";
    }
    if result == "not_allowed" {
        return "Refused: not allowed for their role";
    }
    return "Refused: " + " ".join(result.split("_"));
}

def on_label(event: dict[str, str]) -> str {
    # What it was done to: a cinema by name, else whom (a platform member's email).
    target: str = event["cinema"] or event["resource_id"];
    note: str = event["detail"] or "";
    return target + (f" ({note})" if note else "");
}

def:pub PlatformAuditPage -> JsxElement {
    where: any = useLocation();  # jac:ignore[W1037,W1051]
    win: any = window;  # jac:ignore[W1037,W2001]
    query: any = new(win.URLSearchParams, where.search);  # jac:ignore[W1037]
    cinema: str = query.get("cinema") or "";
    [events, set_events] = useState([]);
    # The `before` cursor of each page reached so far (the first is ""), and which one
    # is shown; the next page's cursor comes with each answer.
    [cursors, set_cursors] = useState([""]);
    [at, set_at] = useState(0);
    [after, set_after] = useState("");
    [total, set_total] = useState(0);
    [action, set_action] = useState("");
    [typed, set_typed] = useState("");
    [search, set_search] = useState("");
    [failed, set_failed] = useState("");
    [loading, set_loading] = useState(True);
    [loaded, set_loaded] = useState(False);

    async def load(chosen: str, wanted: str, before: str) -> bool {
        got: any = None;  # jac:ignore[W1037]
        set_loading(True);
        try {
            got = await platform_audit_log(PAGE, before, chosen, wanted, cinema);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("platform_audit_log failed", e);
            set_loading(False);
            set_failed(
                "We couldn't load the audit log. Refresh the page to try again."
            );
            return False;
        }
        set_loading(False);
        if not got["ok"] {
            set_failed(got["error"]["message"]);
            return False;
        }
        set_failed("");
        set_events(got["events"]);
        set_after(got["next"]);
        set_total(got["total"]);
        set_loaded(True);
        return True;
    }

    def first_page(chosen: str, wanted: str) {
        set_cursors([""]);
        set_at(0);
        load(chosen, wanted, "");
    }

    def start_loading {
        first_page(action, search);
    }
    useEffect(start_loading, [search, cinema]);

    def wait_for_pause -> any {  # jac:ignore[W1037]
        # The search runs once typing pauses, not on every key.
        def run {
            if typed.strip() != search {
                set_search(typed.strip());
            }
        }
        timer: any = win.setTimeout(run, SEARCH_PAUSE_MS);  # jac:ignore[W1037,W6001] client-only debounce
        return lambda { win.clearTimeout(timer); };  # jac:ignore[W6001]
    }
    useEffect(wait_for_pause, [typed]);

    def pick_action(chosen: str) {
        set_action(chosen);
        first_page(chosen, search);
    }

    async def go_next {
        reached: list[str] = cursors;
        cursor: str = after;
        if await load(action, search, cursor) {
            set_cursors(reached[:at + 1] + [cursor]);
            set_at(at + 1);
        }
    }

    async def go_back {
        reached: list[str] = cursors;
        if await load(action, search, reached[at - 1]) {
            set_at(at - 1);
        }
    }

    if not loaded {
        if failed {
            return
                <Alert variant="destructive">
                    <AlertDescription>{failed}</AlertDescription>
                </Alert>;
        }
        return
            <p role="status" className="flex items-center gap-2 text-muted-foreground">
                <Spinner aria-hidden="true"/>
                Loading the audit log…
            </p>;
    }
    zone: str = win.Intl.DateTimeFormat().resolvedOptions().timeZone;
    listed: list[dict[str, str]] = events;
    rows: list[dict[str, str]] = [
        {
            "id": e["event_id"],
            "when": f"{day_label(e['at'], zone)}, {time_label(e['at'], zone)}",
            "who": e["actor"] or "An account that isn't platform staff",
            "what": action_label(e["action"]),
            "on": on_label(e),
            "result": result_label(e["result"])
        } for e in listed
    ];
    count: int = total;
    pages = max(1, int((count + PAGE - 1) / PAGE));
    first_shown = at * PAGE + 1;
    last_shown = at * PAGE + len(rows);
    narrowed = action != "" or search != "" or cinema != "";
    return
        <div className="flex max-w-5xl flex-col gap-4" data-testid="platform-audit">
            <p className="text-sm text-muted-foreground">
                Everything the AfriCinemas team does here, and every attempt that was refused, newest first. Nobody can edit or delete these records.
            </p>
            <div className="flex flex-col gap-3 sm:flex-row sm:items-end">
                <SearchSelect
                    field_id="platform-audit-action"
                    label="Show"
                    value={action}
                    options={ACTIONS}
                    on_pick={pick_action}
                    all_label="Everything"
                    testid="platform-audit-action"
                />
                <div className="flex w-full flex-col gap-1.5 sm:w-72">
                    <Label htmlFor="platform-audit-search">Search who or whom</Label>
                    <Input
                        id="platform-audit-search"
                        type="search"
                        data-testid="platform-audit-search"
                        value={typed}
                        placeholder="An email, a note…"
                        onChange={on_input(set_typed)}
                        className="min-h-11"
                    />
                </div>
            </div>
            {cinema
                and <p
                    className="flex flex-wrap items-center gap-2 text-sm"
                    data-testid="platform-audit-cinema"
                >
                    {f"Only events about {cinema}."}
                    <AppLink
                        to="/audit"
                        className="inline-flex min-h-11 items-center font-medium underline underline-offset-4"
                    >
                        Show every cinema
                    </AppLink>
                </p>}
            {failed
                and <Alert variant="destructive">
                    <AlertDescription>{failed}</AlertDescription>
                </Alert>}
            {len(rows) == 0
                and <p
                    data-testid="platform-audit-empty"
                    className="text-sm text-muted-foreground"
                >
                    {"Nothing matches. Try another action or search."
                        if narrowed
                        else "Nothing recorded yet."}
                </p>}
            {len(rows) > 0
                and <div
                    data-testid="platform-audit-log"
                    aria-busy={"true" if loading else "false"}
                >
                    <ResponsiveTable
                        columns={COLUMNS}
                        rows={rows}
                        caption="Platform audit log, newest first"
                    />
                </div>}
            {len(rows) > 0
                and <nav
                    aria-label="Audit log pages"
                    className="flex flex-wrap items-center justify-between gap-3"
                >
                    <p className="text-sm text-muted-foreground" aria-live="polite">
                        {f"{first_shown}–{last_shown} of {count} {'event'
                            if count == 1
                            else 'events'}"}
                    </p>
                    <div className="flex items-center gap-2">
                        <Button
                            type="button"
                            variant="outline"
                            className="min-h-11 px-4"
                            disabled={loading or at == 0}
                            onClick={go_back}
                        >
                            ← Previous
                        </Button>
                        <span className="px-2 text-sm tabular-nums">
                            {f"Page {at + 1} of {pages}"}
                        </span>
                        <Button
                            type="button"
                            variant="outline"
                            className="min-h-11 px-4"
                            disabled={loading or not after}
                            onClick={go_next}
                        >
                            {loading and <Spinner aria-hidden="true"/>}Next →
                        </Button>
                    </div>
                </nav>}
        </div>;
}
