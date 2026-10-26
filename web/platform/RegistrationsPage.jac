"""`/registrations` in the platform console (P15.0b, ADR-0078): what AfriCinemas
registers outside the app before going live, for super admins (platform.settings).

Each item says what it is and the law behind it. Ticking it asks for a reference (a
certificate number, a note); the list then shows who ticked it and when. Unticking is
one click, and both are in the platform audit log (core/legal/registrations.jac).
"""

import from react { useState, useEffect }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.legal.registrations {
    registrations_checklist,  # jac:ignore[W2037] authenticated endpoint
    tick_registration  # jac:ignore[W2037] authenticated endpoint
}

def _day(iso: str) -> str {
    return iso.split("T")[0] if iso else "";
}

def Item(item: dict[str, any], on_changed: any) -> JsxElement {  # jac:ignore[W1037]
    [reference, set_reference] = useState(item["reference"] or "");
    [busy, set_busy] = useState(False);
    [problem, set_problem] = useState("");
    key: str = item["key"];
    done: bool = bool(item["done"]);

    async def change(want: bool) {
        set_busy(True);
        set_problem("");
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await tick_registration(key, want, reference);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("tick_registration failed", e);
        }
        set_busy(False);
        if got is None or not got["ok"] {
            set_problem(
                got["error"]["message"]
                    if got is not None
                    else "We couldn't save that. Try again."
            );
            return;
        }
        on_changed();
    }

    return
        <li
            data-testid="registration"
            className="flex flex-col gap-3 rounded-lg border bg-card p-4"
        >
            <div className="flex flex-wrap items-start justify-between gap-2">
                <div className="flex flex-col gap-0.5">
                    <p className="font-semibold">{item["what"]}</p>
                    {item["law"]
                        and <p className="text-sm text-muted-foreground">
                            {item["law"]}
                        </p>}
                </div>
                <span
                    data-testid="registration-state"
                    className={"rounded-full px-2 py-0.5 text-xs font-medium "
                        + (
                            "bg-primary text-primary-foreground" if done else "bg-muted"
                        )}
                >
                    {"Done" if done else "To do"}
                </span>
            </div>
            {done
                and <p className="text-sm text-muted-foreground">
                    {f"{item['reference'] or 'No reference'}. Ticked by {item['by']} on {_day(
                        item['at']
                    )}."}
                </p>}
            {not done
                and <div className="flex flex-col gap-1.5">
                    <Label htmlFor={f"ref-{key}"}>Reference (a number or a note)</Label>
                    <Input
                        id={f"ref-{key}"}
                        value={reference}
                        maxLength={200}
                        className="min-h-11"
                        onChange={lambda (e: any) { set_reference(e.target.value); }}  # jac:ignore[W1037]
                    />
                </div>}
            {problem
                and <p role="alert" className="text-sm text-destructive">{problem}</p>}
            <div>
                <Button
                    variant={"outline" if done else "default"}
                    disabled={busy}
                    className="min-h-11"
                    onClick={lambda { change(not done); }}
                >
                    {"Untick" if done else "Mark as done"}
                </Button>
            </div>
        </li>;
}

def:pub RegistrationsPage -> JsxElement {
    [items, set_items] = useState(None);
    [failed, set_failed] = useState(False);

    async def load {
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await registrations_checklist();  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("registrations_checklist failed", e);
        }
        if got is None or not got["ok"] {
            set_failed(True);
            return;
        }
        set_items(got["items"]);
    }

    def start {
        load();
    }
    useEffect(start, []);

    if failed {
        return
            <p role="alert" className="text-sm text-destructive">
                We couldn't load the checklist. Refresh the page to try again.
            </p>;
    }
    shown: list[dict[str, any]] | None = items;  # jac:ignore[W1037]
    if shown is None {
        return <Spinner aria-label="Loading the checklist"/>;
    }
    left = len(
        [
            i
            for i in shown
            if not i["done"]
        ]
    );
    return
        <section data-testid="registrations" className="flex max-w-3xl flex-col gap-4">
            <p className="text-muted-foreground">
                {f"What AfriCinemas registers outside the app before going live. {left} of {len(
                    shown
                )} still to do."}
            </p>
            <ul className="flex flex-col gap-3">
                {[<Item key={i["key"]} item={i} on_changed={load}/> for i in shown]}
            </ul>
        </section>;
}
