"""`/fees` in the platform console (P15.1, ADR-0079): AfriCinemas' fee rule.

For platform staff (platform.read): the rates in force (online tickets, glasses and
booking fee; online snacks; box office) and every version with the day it applies
from and who set it. A super admin (platform.settings) adds a version from today or a
later day (core/legal/fee_rule.jac); changing the rates also needs a new version of the
cinema agreement for cinemas to accept.
"""

import from react { useState, useEffect }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.legal.fee_rule {
    fee_rules,  # jac:ignore[W2037] authenticated endpoint
    set_fee_rule  # jac:ignore[W2037] authenticated endpoint
}

def:pub percent_label(bp: int) -> str {
    whole = bp // 100;
    rest = bp % 100;
    if rest == 0 {
        return f"{whole}%";
    }
    return f"{whole}.{rest // 10}{rest % 10 if rest % 10 else ''}%";
}

def:pub RateField(
    field_id: str,
    label: str,
    value: str,
    on_value: any,  # jac:ignore[W1037]
    kind: str = "text"
) -> JsxElement {
    return
        <div className="flex min-w-0 flex-col gap-1.5">
            <Label htmlFor={field_id}>{label}</Label>
            <Input
                id={field_id}
                type={kind}
                value={value}
                inputMode={"decimal" if kind == "text" else None}
                className="min-h-11"
                onChange={lambda (e: any) { on_value(e.target.value); }}  # jac:ignore[W1037]
            />
        </div>;
}

def:pub FeesPage(may_change: bool = False) -> JsxElement {
    [rules, set_rules] = useState(None);
    [failed, set_failed] = useState(False);
    [ticket, set_ticket] = useState("");
    [snack, set_snack] = useState("");
    [counter, set_counter] = useState("");
    [day, set_day] = useState("");
    [busy, set_busy] = useState(False);
    [note, set_note] = useState("");

    async def load {
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await fee_rules();  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("fee_rules failed", e);
        }
        if got is None or not got["ok"] {
            set_failed(True);
            return;
        }
        set_rules(got);
    }

    def start {
        load();
    }
    useEffect(start, []);

    async def add(e: any) {  # jac:ignore[W1037]
        e.preventDefault();
        set_busy(True);
        set_note("");
        got: any = None;  # jac:ignore[W1037]
        win: any = window;  # jac:ignore[W1037,W2001]
        try {
            got = await set_fee_rule(  # jac:ignore[W2037]
                win.Number(ticket or "x"),
                win.Number(snack or "x"),
                win.Number(counter or "x"),
                day
            );
        } except Exception as err {
            console.warn("set_fee_rule failed", err);
        }
        set_busy(False);
        if got is None or not got["ok"] {
            set_note(
                got["error"]["message"]
                    if got is not None
                    else "We couldn't save that. Try again."
            );
            return;
        }
        set_note(
            f"Version {got['rule']['version']} applies from {got['rule'][
                'applies_from'
            ]}. Publish a new version of the cinema agreement with these rates."
        );
        load();
    }

    if failed {
        return
            <p role="alert" className="text-sm text-destructive">
                We couldn't load the fee rule. Refresh the page to try again.
            </p>;
    }
    shown: dict[str, any] | None = rules;  # jac:ignore[W1037]
    if shown is None {
        return <Spinner aria-label="Loading the fee rule"/>;
    }
    now_rule: dict[str, any] = shown["current"];  # jac:ignore[W1037]
    versions: list[dict[str, any]] = shown["versions"];  # jac:ignore[W1037]
    return
        <section data-testid="fees" className="flex max-w-3xl flex-col gap-6">
            <div
                data-testid="fees-current"
                className="grid gap-3 rounded-lg border bg-card p-4 sm:grid-cols-3"
            >
                <div>
                    <p className="text-sm text-muted-foreground">
                        Online: tickets, glasses, booking fee
                    </p>
                    <p className="text-2xl font-semibold">
                        {percent_label(now_rule["online_ticket_bp"])}
                    </p>
                </div>
                <div>
                    <p className="text-sm text-muted-foreground">Online: snacks</p>
                    <p className="text-2xl font-semibold">
                        {percent_label(now_rule["online_snack_bp"])}
                    </p>
                </div>
                <div>
                    <p className="text-sm text-muted-foreground">
                        Box office: everything
                    </p>
                    <p className="text-2xl font-semibold">
                        {percent_label(now_rule["counter_bp"])}
                    </p>
                </div>
            </div>
            <div className="flex flex-col gap-2">
                <h2 className="text-lg font-semibold">Versions</h2>
                <ul className="flex flex-col gap-2">
                    {[
                        <li
                            key={f"{v['version']}"}
                            data-testid="fee-version"
                            className="rounded-lg border bg-card p-3 text-sm"
                        >
                            {f"Version {v['version']}, from {v['applies_from']}: {percent_label(
                                v['online_ticket_bp']
                            )} tickets, {percent_label(
                                v['online_snack_bp']
                            )} snacks online; {percent_label(
                                v['counter_bp']
                            )} at the box office"
                                + (f". Set by {v['set_by']}." if v["set_by"] else ".")}
                        </li> for v in versions
                    ]}
                </ul>
            </div>
            {may_change
                and <form
                    data-testid="fee-form"
                    className="flex flex-col gap-3 rounded-lg border bg-card p-4"
                    onSubmit={add}
                >
                    <h2 className="text-lg font-semibold">Add a version</h2>
                    <p className="text-sm text-muted-foreground">
                        Rates in percent. A version applies from today or a later day, never to orders already paid.
                    </p>
                    <div className="grid gap-3 sm:grid-cols-2">
                        <RateField
                            field_id="fee-ticket"
                            label="Online tickets, glasses, booking fee (%)"
                            value={ticket}
                            on_value={set_ticket}
                        />
                        <RateField
                            field_id="fee-snack"
                            label="Online snacks (%)"
                            value={snack}
                            on_value={set_snack}
                        />
                        <RateField
                            field_id="fee-counter"
                            label="Box office (%)"
                            value={counter}
                            on_value={set_counter}
                        />
                        <RateField
                            field_id="fee-from"
                            label="Applies from"
                            value={day}
                            on_value={set_day}
                            kind="date"
                        />
                    </div>
                    <div>
                        <Button type="submit" disabled={busy} className="min-h-11">
                            {"Saving…" if busy else "Add version"}
                        </Button>
                    </div>
                    <p
                        role="status"
                        aria-live="polite"
                        className="text-sm empty:hidden"
                    >
                        {note}
                    </p>
                </form>}
        </section>;
}
