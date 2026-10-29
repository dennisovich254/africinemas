"""Tabs for a page with several parts (owner, 2026-10-29: no long lists of sections).

A row of buttons under a border, the current one underlined; it scrolls sideways on
a phone rather than wrapping. Each tab is {"key", "label", "count"}: a count other
than "" shows beside the label (what's waiting, or what needs fixing there). Each button
is `{testid}-{key}`, pressed when it's the current one. The page shows the part itself.
"""

def:pub Tabs(  # jac:ignore[W3030] the row: its name, the tabs, which, what then, test ids
    label: str,
    tabs: list[dict[str, str]],
    current: str,
    on_pick: any,  # jac:ignore[W1037]
    testid: str
) -> JsxElement {
    return
        <div
            role="group"
            aria-label={label}
            className="flex gap-2 overflow-x-auto border-b"
        >
            {[
                <button
                    key={t["key"]}
                    type="button"
                    aria-pressed={"true" if current == t["key"] else "false"}
                    data-testid={f"{testid}-{t['key']}"}
                    onClick={lambda { on_pick(t["key"]); }}
                    className={"-mb-px inline-flex min-h-11 shrink-0 items-center gap-2 whitespace-nowrap border-b-2 px-3 text-sm font-medium "
                        + (
                            "border-primary text-foreground"
                                if current == t["key"]
                                else "border-transparent text-muted-foreground hover:text-foreground"
                        )}
                >
                    {t["label"]}{t.get("count", "")
                        and <span
                            className="rounded-full bg-muted px-2 text-xs tabular-nums"
                        >
                            {t["count"]}
                        </span>}
                </button> for t in tabs
            ]}
        </div>;
}
