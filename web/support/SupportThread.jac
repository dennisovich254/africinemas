"""A help request as a chat (P13.5a, P13.5b), for the cinema's Help section and our inbox.

Like a messaging app: oldest first, the reader's own messages on the right in the
accent colour, the other side's on the left, each with its time underneath, and the
view kept at the newest message. The cinema sees "AfriCinemas" for our messages (never
which of us); we see who of the cinema's staff wrote, and which of us. Text keeps its
line breaks. A message's screenshot shows in its bubble, fetched through the page's
`load_image` (the cinema's own, or ours to read), and opens full size in a new tab.

ChatComposer is the message box under it: Enter sends, Shift+Enter starts a new line,
and the paperclip attaches one screenshot (JPEG, PNG or WebP, up to 3 MB, the server's
limit), shown as a thumbnail that can be removed before sending.
"""

import from react { useEffect, useRef, useState }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { SentIcon, Attachment01Icon, Cancel01Icon }
import from ...components.ui.button { Button }
import from ...components.ui.spinner { Spinner }
import from ...components.ui.textarea { Textarea }
import from ..storefront.showtimes { day_label, time_label }
import from ..backoffice.form_parts { read_as_base64 }

glob IMAGE_TYPES: list[str] = ["image/jpeg", "image/png", "image/webp"],
     IMAGE_MAX_BYTES: int = 3 * 1024 * 1024;

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

def ChatImage(index: int, load_image: any) -> JsxElement {  # jac:ignore[W1037]
    # One message's screenshot, fetched when it's shown.
    [source, set_source] = useState("");
    [failed, set_failed] = useState(False);
    async def fetch {
        try {
            answer: any = await load_image(index);  # jac:ignore[W1037]
            if answer["ok"] {
                set_source(
                    f"data:{answer['content_type']};base64,{answer['data_base64']}"
                );
                return;
            }
        } except Exception as e {
            console.warn("screenshot failed", e);
        }
        set_failed(True);
    }
    def start {
        fetch();
    }
    useEffect(start, [index]);
    if failed {
        return
            <span className="text-xs text-muted-foreground">
                The screenshot couldn't be loaded.
            </span>;
    }
    if not source {
        return
            <span
                className="flex h-24 w-40 items-center justify-center rounded-xl bg-muted"
                role="status"
            >
                <Spinner aria-hidden="true"/>
                <span className="sr-only">Loading the screenshot…</span>
            </span>;
    }
    return
        <a href={source} target="_blank" rel="noreferrer" className="block">
            <img
                src={source}
                alt="Screenshot"
                data-testid="support-image"
                className="max-h-64 max-w-full rounded-xl object-contain"
            />
        </a>;
}

def:pub SupportThread(
    messages: list[dict[str, any]],  # jac:ignore[W1037]
    reader: str,
    cinema: str = "",
    load_image: any = None  # jac:ignore[W1037] (index) -> the screenshot's answer
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
                    <div
                        className={"flex max-w-[85%] flex-col gap-2 rounded-2xl px-3 py-2 text-sm sm:max-w-[75%] "
                            + (
                                "rounded-br-md bg-primary text-primary-foreground"
                                    if m["side"] == reader
                                    else "rounded-bl-md bg-muted text-foreground"
                            )}
                    >
                        {m["has_image"]
                            and load_image
                            and <ChatImage index={i} load_image={load_image}/>}{m[
                            "text"
                        ]
                            and <p className="whitespace-pre-wrap break-words">
                                {m["text"]}
                            </p>}
                    </div>
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
    on_send: any,  # jac:ignore[W1037] (text, image or None) -> bool, true when sent
    placeholder: str = "Message",
    hint: str = ""
) -> JsxElement {
    # `image` handed to on_send: {"type", "data_base64"}, or None.
    [text, set_text] = useState("");
    [image, set_image] = useState(None);
    [preview, set_preview] = useState("");
    [problem, set_problem] = useState("");
    [busy, set_busy] = useState(False);
    picker = useRef(None);

    async def send {
        wanted: str = text;
        if (not wanted.strip() and image is None) or busy {
            return;
        }
        set_busy(True);
        sent: bool = await on_send(wanted, image);
        set_busy(False);
        if sent {
            set_text("");
            set_image(None);
            set_preview("");
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
    async def picked(e: any) {  # jac:ignore[W1037]
        files: any = e.target.files;  # jac:ignore[W1037]
        file: any = files[0] if files and len(files) else None;  # jac:ignore[W1037]
        e.target.value = "";
        if not file {
            return;
        }
        if file.type not in IMAGE_TYPES {
            set_problem("Choose a JPEG, PNG or WebP screenshot.");
            return;
        }
        if file.size > IMAGE_MAX_BYTES {
            set_problem("Choose a screenshot of up to 3 MB.");
            return;
        }
        set_problem("");
        data: str = await read_as_base64(file);
        set_image({"type": file.type, "data_base64": data});
        set_preview(f"data:{file.type};base64,{data}");
    }
    def choose {
        if picker.current {
            picker.current.click();
        }
    }
    def drop_image {
        set_image(None);
        set_preview("");
    }
    return
        <form
            onSubmit={on_submit}
            className="flex flex-col gap-2"
            data-testid="chat-composer"
        >
            {preview
                and <div className="relative w-fit" data-testid="chat-attached">
                    <img
                        src={preview}
                        alt="Screenshot to send"
                        className="max-h-32 rounded-xl ring-1 ring-foreground/10"
                    />
                    <Button
                        type="button"
                        size="icon"
                        variant="secondary"
                        className="absolute -right-2 -top-2 size-11 rounded-full"
                        onClick={drop_image}
                        aria-label="Remove the screenshot"
                    >
                        <HugeiconsIcon
                            icon={Cancel01Icon}
                            strokeWidth={2}
                            aria-hidden="true"
                        />
                    </Button>
                </div>}
            <label htmlFor={field_id} className="sr-only">{label}</label>
            <div className="flex items-end gap-2">
                <input
                    ref={picker}
                    type="file"
                    accept="image/jpeg,image/png,image/webp"
                    className="hidden"
                    data-testid="chat-file"
                    onChange={picked}
                />
                <Button
                    type="button"
                    size="icon"
                    variant="ghost"
                    className="size-11 shrink-0 rounded-full"
                    onClick={choose}
                    aria-label="Attach a screenshot"
                    data-testid="chat-attach"
                >
                    <HugeiconsIcon
                        icon={Attachment01Icon}
                        strokeWidth={2}
                        aria-hidden="true"
                    />
                </Button>
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
                    disabled={busy or (not text.strip() and image is None)}
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
            {problem
                and <p className="px-1 text-xs text-destructive" role="alert">
                    {problem}
                </p>}
            {hint and <p className="px-1 text-xs text-muted-foreground">{hint}</p>}
        </form>;
}
