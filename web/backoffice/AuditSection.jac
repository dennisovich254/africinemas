"""`/app/:slug/audit`: the cinema's audit log (P7.3, on P7.2's audit_log; ADR-0027).

Newest first, PAGE at a time with Previous and Next and "Page 2 of 14 · 340 events"
(improvements #12): the server pages by the last event shown, so new events don't shift
the pages being read. Narrowed by an action picked from a list that filters as you type
(SearchSelect), and by a search of who did it or what it was done to. Each row says when (in the cinema's time zone), who,
what, to what, and the result in words: "Done", "Refused: not allowed", ...
For staff with audit.read (owners, auditors); the server checks it on every request.
Nobody can change or delete an event, so the page has no actions.
"""

import from react { useState, useEffect }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.audit.audit_api { audit_log }  # jac:ignore[W2037] authenticated endpoint
import from ..shell.ResponsiveTable { ResponsiveTable }
import from ..storefront.showtimes { day_label, time_label }
import from .report_view { ACTIONS, action_label, resource_label, result_label }
import from .SearchSelect { SearchSelect }
import from .form_parts { on_input }

glob PAGE: int = 25,
     SEARCH_PAUSE_MS: int = 300,
     COLUMNS: list[dict[str, str]] = [
         {"key": "when", "label": "When"},
         {"key": "who", "label": "Who"},
         {"key": "what", "label": "What"},
         {"key": "on", "label": "On"},
         {"key": "result", "label": "Result"}
     ];

def:pub AuditSection(slug: str, shift_open: bool = True) -> JsxElement {
    [events, set_events] = useState([]);
    # The `before` cursor of each page reached so far (the first is ""), and which one
    # is shown; the next page's cursor comes with each answer.
    [cursors, set_cursors] = useState([""]);
    [at, set_at] = useState(0);
    [after, set_after] = useState("");
    [total, set_total] = useState(0);
    [timezone, set_timezone] = useState("");
    [action, set_action] = useState("");
    # What's typed in the search box, and what's searched (after a pause in typing).
    [typed, set_typed] = useState("");
    [search, set_search] = useState("");
    [failed, set_failed] = useState("");
    [loading, set_loading] = useState(True);
    [loaded, set_loaded] = useState(False);

    async def load(chosen: str, query: str, before: str) -> bool {
        got: any = None;  # jac:ignore[W1037]
        set_loading(True);
        try {
            got = await audit_log(slug, PAGE, before, chosen, query);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("audit_log failed", e);
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
        set_timezone(got["timezone"]);
        set_events(got["events"]);
        set_after(got["next"]);
        set_total(got["total"]);
        set_loaded(True);
        return True;
    }

    def first_page(chosen: str, query: str) {
        set_cursors([""]);
        set_at(0);
        load(chosen, query, "");
    }

    def start_loading {
        first_page(action, search);
    }
    useEffect(start_loading, [slug, shift_open, search]);

    def wait_for_pause -> any {  # jac:ignore[W1037]
        # The search runs once typing pauses, not on every key.
        win: any = window;  # jac:ignore[W1037,W2001]
        def run {
            if typed.strip() != search {
                set_search(typed.strip());
            }
        }
        timer: any = win.setTimeout(run, SEARCH_PAUSE_MS);  # jac:ignore[W1037]
        return lambda { win.clearTimeout(timer); };
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
    listed: list[dict[str, str]] = events;
    rows: list[dict[str, str]] = [
        {
            "id": e["event_id"],
            "when": f"{day_label(e['at'], timezone)}, {time_label(e['at'], timezone)}",
            "who": e["actor"] or "Staff member",
            "what": action_label(e["action"]),
            "on": (
                resource_label(e["resource_type"])
                + (f" ({e['detail']})" if e["detail"] else "")
            ),
            "result": result_label(e["result"])
        } for e in listed
    ];
    count: int = total;
    pages = max(1, int((count + PAGE - 1) / PAGE));
    first_shown = at * PAGE + 1;
    last_shown = at * PAGE + len(rows);
    narrowed = action != "" or search != "";
    return
        <div className="flex flex-col gap-4">
            <p className="text-sm text-muted-foreground">
                Every change your staff make, and every attempt they weren't allowed, newest first. Nobody can edit or delete these records.
            </p>
            <div className="flex flex-col gap-3 sm:flex-row sm:items-end">
                <SearchSelect
                    field_id="audit-action"
                    label="Show"
                    value={action}
                    options={ACTIONS}
                    on_pick={pick_action}
                    all_label="Everything"
                    testid="audit-action"
                />
                <div className="flex w-full flex-col gap-1.5 sm:w-72">
                    <Label htmlFor="audit-search">Search who or what</Label>
                    <Input
                        id="audit-search"
                        type="search"
                        data-testid="audit-search"
                        value={typed}
                        placeholder="A name, a seat, a movie…"
                        onChange={on_input(set_typed)}
                        className="min-h-11"
                    />
                </div>
            </div>
            {failed
                and <Alert variant="destructive">
                    <AlertDescription>{failed}</AlertDescription>
                </Alert>}
            {len(rows) == 0
                and <p
                    data-testid="audit-empty"
                    className="text-sm text-muted-foreground"
                >
                    {"Nothing matches. Try another action or search."
                        if narrowed
                        else "Nothing recorded yet."}
                </p>}
            {len(rows) > 0
                and <div
                    data-testid="audit-log"
                    aria-busy={"true" if loading else "false"}
                >
                    <ResponsiveTable
                        columns={COLUMNS}
                        rows={rows}
                        caption="Audit log, newest first"
                    />
                </div>}
            {len(rows) > 0
                and <nav
                    aria-label="Audit log pages"
                    className="flex flex-wrap items-center justify-between gap-3"
                >
                    <p
                        className="text-sm text-muted-foreground"
                        data-testid="audit-count"
                        aria-live="polite"
                    >
                        {f"{first_shown}–{last_shown} of {count} {'event'
                            if count == 1
                            else 'events'}"}
                    </p>
                    <div className="flex items-center gap-2">
                        <Button
                            type="button"
                            variant="outline"
                            className="min-h-11 px-4"
                            data-testid="audit-prev"
                            disabled={loading or at == 0}
                            onClick={go_back}
                        >
                            ← Previous
                        </Button>
                        <span
                            className="px-2 text-sm tabular-nums"
                            data-testid="audit-page"
                        >
                            {f"Page {at + 1} of {pages}"}
                        </span>
                        <Button
                            type="button"
                            variant="outline"
                            className="min-h-11 px-4"
                            data-testid="audit-next"
                            disabled={loading or not after}
                            onClick={go_next}
                        >
                            {loading and <Spinner aria-hidden="true"/>}Next →
                        </Button>
                    </div>
                </nav>}
        </div>;
}
