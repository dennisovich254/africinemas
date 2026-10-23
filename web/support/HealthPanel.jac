"""A cinema's technical health (P13.5c), on its directory page and beside its requests.

From health_of (core/support/health.jac): each signal's name, its count and what it
counts over. A signal that's up says "Needs a look" with an icon, never by colour
alone; a cinema with none up says it's all clear. `compact` folds the list under a
one-line summary (a help request's page, where the chat comes first).
"""

import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Alert02Icon, CheckmarkCircle02Icon }
import from ..backoffice.report_view { money_label }

def summary_of(problems: int) -> str {
    if problems == 0 {
        return "All clear";
    }
    return f"{problems} {'thing needs' if problems == 1 else 'things need'} a look";
}

def Signals(signals: list[dict[str, any]], currency: str) -> JsxElement {  # jac:ignore[W1037]
    return
        <ul className="flex flex-col divide-y" data-testid="health-signals">
            {[
                <li
                    key={s["key"]}
                    data-testid={f"health-{s['key']}"}
                    className="flex items-start justify-between gap-3 py-2 text-sm"
                >
                    <span className="flex min-w-0 flex-col">
                        <span className={"font-medium" if s["up"] else ""}>
                            {s["label"]}
                        </span>
                        <span className="text-xs text-muted-foreground">
                            {s["note"]}
                        </span>
                    </span>
                    <span className="flex shrink-0 flex-col items-end">
                        <span className="tabular-nums font-semibold">
                            {str(s["count"])
                                + (
                                    f" · {money_label(s['amount_cents'], currency)}"
                                        if s["key"] == "refunds_due" and s["count"] > 0
                                        else ""
                                )}
                        </span>
                        {s["up"]
                            and <span
                                className="flex items-center gap-1 text-xs font-medium text-destructive"
                            >
                                <HugeiconsIcon
                                    icon={Alert02Icon}
                                    size={14}
                                    strokeWidth={2}
                                    aria-hidden="true"
                                />
                                Needs a look
                            </span>}
                    </span>
                </li> for s in signals
            ]}
        </ul>;
}

def:pub HealthPanel(health: dict[str, any], compact: bool = False) -> JsxElement {  # jac:ignore[W1037]
    signals: list[dict[str, any]] = health["signals"] or [];  # jac:ignore[W1037]
    problems: int = health["problems"] or 0;
    title = <span className="flex items-center gap-2 font-semibold">
        <HugeiconsIcon
            icon={Alert02Icon if problems else CheckmarkCircle02Icon}
            strokeWidth={2}
            aria-hidden="true"
            className={"text-destructive" if problems else "text-muted-foreground"}
        />
        {f"Health · {summary_of(problems)}"}
    </span>;
    if compact {
        return
            <details
                className="rounded-lg border bg-card px-3 py-2"
                data-testid="health-panel"
                open={problems > 0}
            >
                <summary className="flex min-h-11 cursor-pointer items-center text-sm">
                    {title}
                </summary>
                <Signals signals={signals} currency={health["currency"]}/>
            </details>;
    }
    return
        <section
            className="flex flex-col gap-1 rounded-lg border bg-card p-4"
            data-testid="health-panel"
        >
            <h3>{title}</h3>
            <p className="text-xs text-muted-foreground">
                Counts from the cinema's own records, for technical problems. No customer's details.
            </p>
            <Signals signals={signals} currency={health["currency"]}/>
        </section>;
}
