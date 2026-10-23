"""A help request's messages (P13.5a), for the cinema's Help section and our inbox.

Oldest first. Each message says who wrote it, from the reader's side: the cinema sees
"You" for its own staff and "AfriCinemas" for ours; we see the cinema's name and the
sender's email, and "AfriCinemas" with ours. Text keeps its line breaks.
"""

import from ..storefront.showtimes { day_label, time_label }

def:pub when(at: str) -> str {
    win: any = window;  # jac:ignore[W1037,W2001]
    zone: str = win.Intl.DateTimeFormat().resolvedOptions().timeZone;
    return f"{day_label(at, zone)}, {time_label(at, zone)}";
}

def:pub SupportThread(
    messages: list[dict[str, str]], reader: str, cinema: str = ""
) -> JsxElement {
    # `reader`: "cinema" or "africinemas", whose page this is.
    return
        <ol className="flex flex-col gap-3" data-testid="support-thread">
            {[
                <li
                    key={f"{m['at']}-{i}"}
                    data-testid="support-message"
                    className={"flex flex-col gap-1 rounded-lg p-3 "
                        + (
                            "bg-muted"
                                if m["side"] == "africinemas"
                                else "border bg-card"
                        )}
                >
                    <span className="flex flex-wrap items-baseline gap-x-2 text-sm">
                        <span className="font-medium">
                            {(
                                "AfriCinemas"
                                + (
                                    f" ({m['by']})"
                                        if reader == "africinemas" and m["by"]
                                        else ""
                                )
                            )
                                if m["side"] == "africinemas"
                                else ("You" if reader == "cinema" else cinema)}
                        </span>
                        {m["side"] == "cinema"
                            and m["by"]
                            and <span className="break-all text-muted-foreground">
                                {m["by"]}
                            </span>}
                        <span className="text-muted-foreground">{when(m["at"])}</span>
                    </span>
                    <p className="whitespace-pre-wrap break-words text-sm">
                        {m["text"]}
                    </p>
                </li> for (i, m) in enumerate(messages)
            ]}
        </ol>;
}
