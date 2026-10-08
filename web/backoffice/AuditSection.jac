"""`/app/:slug/audit`: the cinema's audit log (P7.3, on P7.2's audit_log; ADR-0027).

Newest first, a page at a time ("Load more" asks for the events after the last one
shown), optionally one action. Each row says when (in the cinema's time zone), who,
what, to what, and the result in words: "Done", "Refused: not allowed", ...
For staff with audit.read (owners, auditors); the server checks it on every request.
Nobody can change or delete an event, so the page has no actions.
"""

import from react { useState, useEffect }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.button { Button }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.audit.audit_api { audit_log }  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)
import from ..shell.ResponsiveTable { ResponsiveTable }
import from ..storefront.showtimes { day_label, time_label }
import from .report_view { ACTIONS, action_label, resource_label, result_label }

glob PAGE: int = 50,
     SELECT_CLASSES: str = "min-h-11 w-full rounded-md border border-input bg-background px-3 text-sm sm:w-auto",
     COLUMNS: list[dict[str, str]] = [
         {"key": "when", "label": "When"},
         {"key": "who", "label": "Who"},
         {"key": "what", "label": "What"},
         {"key": "on", "label": "On"},
         {"key": "result", "label": "Result"}
     ];

def:pub AuditSection(slug: str, shift_open: bool = True) -> JsxElement {
    [events, set_events] = useState([]);
    [after, set_after] = useState("");
    [timezone, set_timezone] = useState("");
    [action, set_action] = useState("");
    [failed, set_failed] = useState("");
    [loading, set_loading] = useState(True);
    [loaded, set_loaded] = useState(False);

    async def load(chosen: str, before: str, more: bool) {
        got: any = None;  # jac:ignore[W1037]
        set_loading(True);
        try {
            got = await audit_log(slug, PAGE, before, chosen);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("audit_log failed", e);
            set_loading(False);
            set_failed(
                "We couldn't load the audit log. Refresh the page to try again."
            );
            return;
        }
        set_loading(False);
        if not got["ok"] {
            set_failed(got["error"]["message"]);
            return;
        }
        set_failed("");
        set_timezone(got["timezone"]);
        shown: list[dict[str, str]] = events;
        set_events(shown + got["events"] if more else got["events"]);
        set_after(got["next"]);
        set_loaded(True);
    }

    def start_loading {
        load(action, "", False);
    }
    useEffect(start_loading, [slug, shift_open]);

    def pick_action(e: any) {  # jac:ignore[W1037]
        chosen: str = e.target.value;
        set_action(chosen);
        load(chosen, "", False);
    }

    def load_more {
        load(action, after, True);
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
    return
        <div className="flex flex-col gap-4">
            <p className="text-sm text-muted-foreground">
                Every change your staff make, and every attempt they weren't allowed, newest first. Nobody can edit or delete these records.
            </p>
            <div className="flex flex-col gap-1 sm:flex-row sm:items-center sm:gap-3">
                <Label htmlFor="audit-action">Show</Label>
                <select
                    id="audit-action"
                    data-testid="audit-action"
                    className={SELECT_CLASSES}
                    value={action}
                    onChange={pick_action}
                >
                    <option value="">Everything</option>
                    {[
                        <option key={code} value={code}>{label}</option>
                        for (code, label) in ACTIONS
                    ]}
                </select>
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
                    Nothing recorded yet.
                </p>}
            {len(rows) > 0
                and <div data-testid="audit-log">
                    <ResponsiveTable
                        columns={COLUMNS}
                        rows={rows}
                        caption="Audit log, newest first"
                    />
                </div>}
            {after
                and <Button
                    type="button"
                    variant="outline"
                    className="min-h-11 self-start"
                    data-testid="audit-more"
                    disabled={loading}
                    onClick={load_more}
                >
                    {loading and <Spinner aria-hidden="true"/>}Load more
                </Button>}
        </div>;
}
