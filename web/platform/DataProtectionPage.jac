"""`/data-protection` in the platform console (P15.0): the requests and breach registers.

For super admins (platform.settings), in two tabs (core/legal/dp_registers.jac):
- Requests: log one (who, how to reach them, what they ask, its kind, and the cinema
  if they're its customer); each shows when it's due (and when to pass it on), overdue
  in red, and its steps; record the next step with a note.
- Breaches: log one (when we became aware, what happened, our role); each shows its
  clocks (cinemas within 48 hours, the Commissioner within 72), late in red, the
  assessment, and its steps.
Open ones first. Nothing is deleted: a step is added to the entry. Times are this
browser's.
"""

import from react { useState, useEffect }
import from ...components.ui.badge { Badge }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from ...components.ui.textarea { Textarea }
import from core.legal.dp_registers {
    dp_registers,  # jac:ignore[W2037] authenticated endpoint
    log_data_request,  # jac:ignore[W2037]
    data_request_step,  # jac:ignore[W2037]
    log_breach,  # jac:ignore[W2037]
    assess_breach,  # jac:ignore[W2037]
    breach_step  # jac:ignore[W2037]
}
import from ..backoffice.form_parts { on_input }
import from ..shell.Tabs { Tabs }
import from ..storefront.showtimes { day_time_label }

glob CARD: str = "flex flex-col gap-3 rounded-lg border bg-card p-4",
     SELECT: str = "min-h-11 rounded-md border bg-background px-3";

def _tz -> str {
    win: any = window;  # jac:ignore[W1037,W2001]
    return win.Intl.DateTimeFormat().resolvedOptions().timeZone;
}

def _iso(local: str) -> str {
    # A datetime-local value as an ISO time with its offset; "" for now.
    if not local {
        return "";
    }
    return new(Date, local).toISOString();  # jac:ignore[W2001]
}

def label_of(pairs: list[list[str]], key: str, fallback: str = "") -> str {
    # The label for `key` in the server's [key, label] pairs.
    for pair in pairs {
        if pair[0] == key {
            return pair[1];
        }
    }
    return fallback;
}

def _problem(got: any) -> str {  # jac:ignore[W1037]
    if got is None {
        return "We couldn't reach AfriCinemas. Try again.";
    }
    return got["error"]["message"];
}

def Events(events: list[dict[str, str]], labels: list[list[str]]) -> JsxElement {
    tz = _tz();
    return
        <ol className="flex flex-col gap-1 text-sm" data-testid="dp-events">
            {[
                <li key={f"{i}"}>
                    <span className="font-medium">
                        {label_of(labels, e["step"], "Logged")}
                    </span>
                    <span className="text-muted-foreground">
                        {f" · {day_time_label(e['at'], tz)} · {e['by']}"}
                    </span>
                    {e["note"]
                        and <span className="block text-muted-foreground">
                            {e["note"]}
                        </span>}
                </li> for (i, e) in enumerate(events)
            ]}
        </ol>;
}

def StepForm(  # jac:ignore[W3030] the entry, its steps, what saving does, what then
    entry_id: str,
    steps: list[list[str]],
    save: any,  # jac:ignore[W1037] async (step, note) -> answer
    on_saved: any  # jac:ignore[W1037]
) -> JsxElement {
    [step, set_step] = useState("note");
    [note, set_note] = useState("");
    [busy, set_busy] = useState(False);
    [problem, set_problem] = useState("");

    async def send(e: any) {  # jac:ignore[W1037]
        e.preventDefault();
        set_busy(True);
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await save(step, note);
        } except Exception as err {
            console.warn("saving the step failed", err);
        }
        set_busy(False);
        if got is None or not got["ok"] {
            set_problem(_problem(got));
            return;
        }
        set_problem("");
        set_note("");
        set_step("note");
        on_saved();
    }

    return
        <form className="flex flex-col gap-2 border-t pt-3" onSubmit={send}>
            <div className="flex flex-col gap-1.5 sm:flex-row sm:items-end">
                <div className="flex flex-col gap-1.5">
                    <Label htmlFor={f"step-{entry_id}"}>What was done</Label>
                    <select
                        id={f"step-{entry_id}"}
                        value={step}
                        onChange={on_input(set_step)}
                        className={SELECT}
                    >
                        {[
                            <option key={p[0]} value={p[0]}>{p[1]}</option>
                            for p in steps
                        ]}
                    </select>
                </div>
                <div className="flex flex-1 flex-col gap-1.5">
                    <Label htmlFor={f"note-{entry_id}"}>Note</Label>
                    <Input
                        id={f"note-{entry_id}"}
                        value={note}
                        onChange={on_input(set_note)}
                        className="min-h-11"
                    />
                </div>
                <Button
                    type="submit"
                    variant="outline"
                    className="min-h-11"
                    disabled={busy}
                >
                    Add
                </Button>
            </div>
            <p role="alert" className="text-sm text-destructive empty:hidden">
                {problem}
            </p>
        </form>;
}

def RequestCard(
    r: dict[str, any],  # jac:ignore[W1037]
    steps: list[list[str]],
    on_saved: any  # jac:ignore[W1037]
) -> JsxElement {
    tz = _tz();
    async def save(step: str, note: str) -> any {  # jac:ignore[W1037]
        return await data_request_step(r["id"], step, note);  # jac:ignore[W2037]
    }
    return
        <li className={CARD} data-testid="dp-request">
            <div className="flex flex-wrap items-center gap-2">
                <span className="font-semibold">
                    {f"{r['id']} · {r['kind_label']}"}
                </span>
                <Badge variant="outline">{label_of(steps, r["status"], "Open")}</Badge>
                {r["overdue"]
                    and <Badge variant="destructive" data-testid="dp-overdue">
                        Overdue
                    </Badge>}
            </div>
            <p className="text-sm">
                {f"{r['person']}{' · ' + r['contact'] if r['contact'] else ''}{' · a customer of '
                    + r['cinema']
                    if r['cinema']
                    else ''}"}
            </p>
            <p className="text-sm break-words">{r["asked"]}</p>
            <p className="text-sm text-muted-foreground">
                {f"Received {day_time_label(r['received_at'], tz)} · due {day_time_label(
                    r['due'], tz
                )}"
                    + (
                        f" · pass to the cinema by {day_time_label(r['pass_by'], tz)}"
                            if r["pass_by"]
                            else ""
                    )}
            </p>
            <Events events={r["events"]} labels={steps}/>
            {r["open"]
                and <StepForm
                    entry_id={r["id"]}
                    steps={steps}
                    save={save}
                    on_saved={on_saved}
                />}
        </li>;
}

def AssessForm(b: dict[str, any], on_saved: any) -> JsxElement {  # jac:ignore[W1037]
    [notifiable, set_notifiable] = useState(b["notifiable"]);
    [why, set_why] = useState(b["why"]);
    [data, set_data] = useState(b["data"]);
    [people, set_people] = useState(b["people"]);
    [cinemas, set_cinemas] = useState(b["cinemas"]);
    [problem, set_problem] = useState("");

    async def send(e: any) {  # jac:ignore[W1037]
        e.preventDefault();
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await assess_breach(  # jac:ignore[W2037]
                b["id"],
                {
                    "notifiable": notifiable,
                    "why": why,
                    "data": data,
                    "people": people,
                    "cinemas": cinemas
                }
            );
        } except Exception as err {
            console.warn("assess_breach failed", err);
        }
        if got is None or not got["ok"] {
            set_problem(_problem(got));
            return;
        }
        set_problem("");
        on_saved();
    }

    return
        <form className="grid gap-2 border-t pt-3 sm:grid-cols-2" onSubmit={send}>
            {[
                <div key={key} className="flex flex-col gap-1.5">
                    <Label htmlFor={f"{key}-{b['id']}"}>{label}</Label>
                    <Input
                        id={f"{key}-{b['id']}"}
                        value={value}
                        onChange={on_input(put)}
                        className="min-h-11"
                    />
                </div>
                for (key, label, value, put) in [
                    ("data", "What data", data, set_data),
                    ("people", "How many people", people, set_people),
                    ("cinemas", "Which cinemas", cinemas, set_cinemas)
                ]
            ]}
            <div className="flex flex-col gap-1.5">
                <Label htmlFor={f"notifiable-{b['id']}"}>Notifiable?</Label>
                <select
                    id={f"notifiable-{b['id']}"}
                    value={notifiable}
                    onChange={on_input(set_notifiable)}
                    className={SELECT}
                >
                    <option value="unsure">Not decided yet</option>
                    <option value="yes">Yes</option>
                    <option value="no">No</option>
                </select>
            </div>
            <div className="flex flex-col gap-1.5 sm:col-span-2">
                <Label htmlFor={f"why-{b['id']}"}>Why</Label>
                <Input
                    id={f"why-{b['id']}"}
                    value={why}
                    onChange={on_input(set_why)}
                    className="min-h-11"
                />
            </div>
            <div>
                <Button type="submit" variant="outline" className="min-h-11">
                    Save the assessment
                </Button>
            </div>
            <p
                role="alert"
                className="text-sm text-destructive empty:hidden sm:col-span-2"
            >
                {problem}
            </p>
        </form>;
}

def BreachCard(
    b: dict[str, any],  # jac:ignore[W1037]
    steps: list[list[str]],
    on_saved: any  # jac:ignore[W1037]
) -> JsxElement {
    tz = _tz();
    async def save(step: str, note: str) -> any {  # jac:ignore[W1037]
        return await breach_step(b["id"], step, note);  # jac:ignore[W2037]
    }
    late: list[str] = b["late"];
    choices = [
        p
        for p in steps
        if p[0] != "assessed"
    ];
    return
        <li className={CARD} data-testid="dp-breach">
            <div className="flex flex-wrap items-center gap-2">
                <span className="font-semibold">{b["id"]}</span>
                <Badge variant="outline">{b["role_label"]}</Badge>
                {not b["open"] and <Badge variant="secondary">Closed</Badge>}
                {[
                    <Badge key={l} variant="destructive" data-testid="dp-late">
                        {f"Late: {label_of(steps, l)}"}
                    </Badge> for l in late
                ]}
            </div>
            <p className="text-sm break-words">{b["what"]}</p>
            <p className="text-sm text-muted-foreground">
                {f"Aware {day_time_label(b['aware_at'], tz)}"
                    + (
                        f" · tell cinemas by {day_time_label(b['cinemas_by'], tz)}"
                            if b["cinemas_by"]
                            else ""
                    )
                    + (
                        f" · notify the Commissioner by {day_time_label(
                            b['commissioner_by'], tz
                        )}"
                            if b["commissioner_by"]
                            else ""
                    )}
            </p>
            <Events events={b["events"]} labels={steps}/>
            {b["open"] and <AssessForm b={b} on_saved={on_saved}/>}
            {b["open"]
                and <StepForm
                    entry_id={b["id"]}
                    steps={choices}
                    save={save}
                    on_saved={on_saved}
                />}
        </li>;
}

def NewRequest(kinds: list[list[str]], on_saved: any) -> JsxElement {  # jac:ignore[W1037]
    [kind, set_kind] = useState("access");
    [person, set_person] = useState("");
    [contact, set_contact] = useState("");
    [cinema, set_cinema] = useState("");
    [asked, set_asked] = useState("");
    [received, set_received] = useState("");
    [problem, set_problem] = useState("");

    async def send(e: any) {  # jac:ignore[W1037]
        e.preventDefault();
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await log_data_request(  # jac:ignore[W2037]
                {
                    "kind": kind,
                    "person": person,
                    "contact": contact,
                    "cinema": cinema,
                    "asked": asked,
                    "received_at": _iso(received)
                }
            );
        } except Exception as err {
            console.warn("log_data_request failed", err);
        }
        if got is None or not got["ok"] {
            set_problem(_problem(got));
            return;
        }
        set_problem("");
        set_person("");
        set_contact("");
        set_cinema("");
        set_asked("");
        set_received("");
        on_saved();
    }

    return
        <form className={CARD} onSubmit={send} data-testid="dp-new-request">
            <h2 className="font-semibold">Log a request</h2>
            <div className="grid gap-3 sm:grid-cols-2">
                <div className="flex flex-col gap-1.5">
                    <Label htmlFor="dp-kind">What they ask for</Label>
                    <select
                        id="dp-kind"
                        value={kind}
                        onChange={on_input(set_kind)}
                        className={SELECT}
                    >
                        {[
                            <option key={p[0]} value={p[0]}>{p[1]}</option>
                            for p in kinds
                        ]}
                    </select>
                </div>
                <div className="flex flex-col gap-1.5">
                    <Label htmlFor="dp-received">Received (leave empty for now)</Label>
                    <Input
                        id="dp-received"
                        type="datetime-local"
                        value={received}
                        onChange={on_input(set_received)}
                        className="min-h-11"
                    />
                </div>
                <div className="flex flex-col gap-1.5">
                    <Label htmlFor="dp-person">Who</Label>
                    <Input
                        id="dp-person"
                        value={person}
                        onChange={on_input(set_person)}
                        className="min-h-11"
                    />
                </div>
                <div className="flex flex-col gap-1.5">
                    <Label htmlFor="dp-contact">How to reach them</Label>
                    <Input
                        id="dp-contact"
                        value={contact}
                        onChange={on_input(set_contact)}
                        className="min-h-11"
                    />
                </div>
                <div className="flex flex-col gap-1.5 sm:col-span-2">
                    <Label htmlFor="dp-cinema">
                        The cinema, if they're its customer (its web address)
                    </Label>
                    <Input
                        id="dp-cinema"
                        value={cinema}
                        onChange={on_input(set_cinema)}
                        className="min-h-11"
                    />
                </div>
                <div className="flex flex-col gap-1.5 sm:col-span-2">
                    <Label htmlFor="dp-asked">What they ask, in their words</Label>
                    <Textarea
                        id="dp-asked"
                        rows={3}
                        value={asked}
                        onChange={on_input(set_asked)}
                    />
                </div>
            </div>
            <div>
                <Button type="submit" className="min-h-11">Log the request</Button>
            </div>
            <p role="alert" className="text-sm text-destructive empty:hidden">
                {problem}
            </p>
        </form>;
}

def NewBreach(roles: list[list[str]], on_saved: any) -> JsxElement {  # jac:ignore[W1037]
    [role, set_role] = useState("both");
    [what, set_what] = useState("");
    [aware, set_aware] = useState("");
    [problem, set_problem] = useState("");

    async def send(e: any) {  # jac:ignore[W1037]
        e.preventDefault();
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await log_breach(
                {"role": role, "what": what, "aware_at": _iso(aware)}
            );  # jac:ignore[W2037]
        } except Exception as err {
            console.warn("log_breach failed", err);
        }
        if got is None or not got["ok"] {
            set_problem(_problem(got));
            return;
        }
        set_problem("");
        set_what("");
        set_aware("");
        on_saved();
    }

    return
        <form className={CARD} onSubmit={send} data-testid="dp-new-breach">
            <h2 className="font-semibold">Log a breach</h2>
            <p className="text-sm text-muted-foreground">
                Log it as soon as anyone is reasonably sure it happened: the clocks start then.
            </p>
            <div className="grid gap-3 sm:grid-cols-2">
                <div className="flex flex-col gap-1.5">
                    <Label htmlFor="dp-role">Whose data</Label>
                    <select
                        id="dp-role"
                        value={role}
                        onChange={on_input(set_role)}
                        className={SELECT}
                    >
                        {[
                            <option key={p[0]} value={p[0]}>{p[1]}</option>
                            for p in roles
                        ]}
                    </select>
                </div>
                <div className="flex flex-col gap-1.5">
                    <Label htmlFor="dp-aware">
                        We became aware (leave empty for now)
                    </Label>
                    <Input
                        id="dp-aware"
                        type="datetime-local"
                        value={aware}
                        onChange={on_input(set_aware)}
                        className="min-h-11"
                    />
                </div>
                <div className="flex flex-col gap-1.5 sm:col-span-2">
                    <Label htmlFor="dp-what">What happened</Label>
                    <Textarea
                        id="dp-what"
                        rows={3}
                        value={what}
                        onChange={on_input(set_what)}
                    />
                </div>
            </div>
            <div>
                <Button type="submit" className="min-h-11">Log the breach</Button>
            </div>
            <p role="alert" className="text-sm text-destructive empty:hidden">
                {problem}
            </p>
        </form>;
}

def:pub DataProtectionPage -> JsxElement {
    [shown, set_shown] = useState(None);
    [tab, set_tab] = useState("requests");

    async def load {
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await dp_registers();  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("dp_registers failed", e);
        }
        if got is not None and got["ok"] {
            set_shown(got);
        }
    }

    def start {
        load();
    }
    useEffect(start, []);

    found: dict[str, any] | None = shown;  # jac:ignore[W1037]
    if found is None {
        return <Spinner/>;
    }
    requests: list[dict[str, any]] = found["requests"];  # jac:ignore[W1037]
    breaches: list[dict[str, any]] = found["breaches"];  # jac:ignore[W1037]
    open_requests = len(
        [
            r
            for r in requests
            if r["open"]
        ]
    );
    open_breaches = len(
        [
            b
            for b in breaches
            if b["open"]
        ]
    );
    return
        <div className="flex max-w-3xl flex-col gap-4" data-testid="data-protection">
            <p className="text-sm text-muted-foreground">
                The registers the law asks us to keep: people's requests about their data, and every breach, notifiable or not. Nothing here is deleted; each step is added.
            </p>
            <Tabs
                label="Registers"
                tabs={[
                    {
                        "key": "requests",
                        "label": "Requests",
                        "count": str(open_requests) if open_requests > 0 else ""
                    },
                    {
                        "key": "breaches",
                        "label": "Breaches",
                        "count": str(open_breaches) if open_breaches > 0 else ""
                    }
                ]}
                current={tab}
                on_pick={set_tab}
                testid="dp-tab"
            />
            {tab == "requests"
                and <div className="flex flex-col gap-4">
                    <NewRequest kinds={found["kinds"]} on_saved={load}/>
                    {len(requests) == 0
                        and <p className="text-sm text-muted-foreground">
                            No requests yet.
                        </p>}
                    <ul className="flex flex-col gap-3">
                        {[
                            <RequestCard
                                key={r["id"]}
                                r={r}
                                steps={found["request_steps"]}
                                on_saved={load}
                            /> for r in requests
                        ]}
                    </ul>
                </div>}
            {tab == "breaches"
                and <div className="flex flex-col gap-4">
                    <NewBreach roles={found["roles"]} on_saved={load}/>
                    {len(breaches) == 0
                        and <p className="text-sm text-muted-foreground">
                            No breaches recorded.
                        </p>}
                    <ul className="flex flex-col gap-3">
                        {[
                            <BreachCard
                                key={b["id"]}
                                b={b}
                                steps={found["breach_steps"]}
                                on_saved={load}
                            /> for b in breaches
                        ]}
                    </ul>
                </div>}
        </div>;
}
