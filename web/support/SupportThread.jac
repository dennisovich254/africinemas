"""A help request as a chat (P13.5a), for the cinema's Help section and our inbox.

Like a messaging app: oldest first, the reader's own messages on the right in the
accent colour, the other side's on the left, each with its time underneath, and the
view kept at the newest message. The cinema sees "AfriCinemas" for our messages (never
which of us); we see who of the cinema's staff wrote, and which of us. Text keeps its
line breaks. ChatComposer is the message box under it: Enter sends, Shift+Enter starts
a new line.
"""

import from react { useEffect, useRef, useState }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { SentIcon }
import from ...components.ui.button { Button }
import from ...components.ui.spinner { Spinner }
import from ...components.ui.textarea { Textarea }
import from ..storefront.showtimes { day_label, time_label }

def:pub when(at: str) -> str {
    win: any = window;  # jac:ignore[W1037,W2001]
    zone: str = win.Intl.DateTimeFormat().resolvedOptions().timeZone;
    return f"{day_label(at, zone)}, {time_label(at, zone)}";
}

def _author(message: dict[str, str], reader: str, cinema: str) -> str {
    # The name over the other side's message ("" over the reader's own).
    if message["side"] == reader {
        return "";
    }
    if message["side"] == "africinemas" {
        return "AfriCinemas";
    }
    return f"{cinema} · {message['by']}" if message["by"] else cinema;
}

def:pub SupportThread(
    messages: list[dict[str, str]], reader: str, cinema: str = ""
) -> JsxElement {
    # `reader`: "cinema" or "africinemas", whose page this is.
    end = useRef(None);
    def to_newest {
        if end.current {
            end.current.scrollIntoView({"block": "nearest"});
        }
    }
    useEffect(to_newest, [len(messages)]);
    return
        <ol
            className="flex flex-col gap-2"
            data-testid="support-thread"
            aria-label="Messages, oldest first"
        >
            {[
                <li
                    key={f"{m['at']}-{i}"}
                    data-testid="support-message"
                    className={"flex flex-col gap-1 "
                        + ("items-end" if m["side"] == reader else "items-start")}
                >
                    {_author(m, reader, cinema)
                        and <span
                            className="max-w-full break-all px-1 text-xs font-medium text-muted-foreground"
                        >
                            {_author(m, reader, cinema)}
                        </span>}
                    <p
                        className={"max-w-[85%] whitespace-pre-wrap break-words rounded-2xl px-3 py-2 text-sm sm:max-w-[75%] "
                            + (
                                "rounded-br-md bg-primary text-primary-foreground"
                                    if m["side"] == reader
                                    else "rounded-bl-md bg-muted text-foreground"
                            )}
                    >
                        {m["text"]}
                    </p>
                    <span className="px-1 text-xs text-muted-foreground">
                        {when(m["at"])}{m["side"] == reader
                            and reader == "africinemas"
                            and m["by"]
                            and f" · {m['by']}"}
                    </span>
                </li> for (i, m) in enumerate(messages)
            ]}
            <li ref={end} aria-hidden="true"/>
        </ol>;
}

def:pub ChatComposer(
    field_id: str,
    label: str,
    on_send: any,  # jac:ignore[W1037] (text) -> bool, true when sent
    placeholder: str = "Message",
    hint: str = ""
) -> JsxElement {
    [text, set_text] = useState("");
    [busy, set_busy] = useState(False);
    async def send {
        wanted: str = text;
        if not wanted.strip() or busy {
            return;
        }
        set_busy(True);
        sent: bool = await on_send(wanted);
        set_busy(False);
        if sent {
            set_text("");
        }
    }
    def on_key(e: any) {  # jac:ignore[W1037]
        if e.key == "Enter" and not e.shiftKey {
            e.preventDefault();
            send();
        }
    }
    def on_submit(e: any) {  # jac:ignore[W1037]
        e.preventDefault();
        send();
    }
    return
        <form
            onSubmit={on_submit}
            className="flex flex-col gap-1"
            data-testid="chat-composer"
        >
            <label htmlFor={field_id} className="sr-only">{label}</label>
            <div className="flex items-end gap-2">
                <Textarea
                    id={field_id}
                    value={text}
                    rows={1}
                    placeholder={placeholder}
                    onChange={lambda (e: any) { set_text(e.target.value); }}  # jac:ignore[W1037]
                    onKeyDown={on_key}
                    className="max-h-40 min-h-11 flex-1 resize-none rounded-2xl"
                />
                <Button
                    type="submit"
                    size="icon"
                    className="size-11 shrink-0 rounded-full"
                    disabled={busy or not text.strip()}
                    aria-label="Send"
                    data-testid="chat-send"
                >
                    {busy and <Spinner aria-hidden="true"/>}{not busy
                        and <HugeiconsIcon
                            icon={SentIcon}
                            strokeWidth={2}
                            aria-hidden="true"
                        />}
                </Button>
            </div>
            {hint and <p className="px-1 text-xs text-muted-foreground">{hint}</p>}
        </form>;
}
