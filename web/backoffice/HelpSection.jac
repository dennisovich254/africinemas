"""`/app/:slug/help` and `/app/:slug/help/:id`: asking AfriCinemas for help (P13.5a).

For staff with support.request (owners, tenant admins, general and finance managers),
laid out like a messaging app. The list is the cinema's conversations, newest first:
what each is about, its last message and whose turn it is, and "New request" (what
it's about, then the first message). A conversation opens as a chat
(web/support/SupportThread.jac) with the message box at the bottom; the phone's back
button returns to the list. New messages appear without a refresh: an open chat asks
every few seconds, the list less often (web/support/live.jac). The server checks every
request (core/support/requests.jac).
"""

import from react { useState, useEffect }
import from "@jac/runtime" { useNavigate }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Add01Icon }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.badge { Badge }
import from ...components.ui.button { Button }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.support.requests {
    ask_for_help,  # jac:ignore[W2037] authenticated endpoint
    support_requests,  # jac:ignore[W2037]
    reply_to_support,  # jac:ignore[W2037]
    support_seen  # jac:ignore[W2037]
}
import from .form_parts { on_input }
import from .nav { section_path }
import from ..shell.AppLink { AppLink }
import from ..support.SupportThread { SupportThread, ChatComposer, when }
import from ..support.live { use_every, seen_now, CHAT_MS, LIST_MS }

glob OFFLINE: str = "We couldn't reach AfriCinemas. Check your connection and try again.",
     SELECT_CLASSES: str = "min-h-11 rounded-md border border-input bg-background px-3 text-sm",
     PRIVATE_HINT: str = "Never include passwords, PINs or card numbers.";

def last_text(request: dict[str, any]) -> str {  # jac:ignore[W1037]
    messages: list[dict[str, str]] = request["messages"];
    return messages[len(messages) - 1]["text"] if messages else "";
}

def:pub HelpSection(slug: str, shift_open: bool = True, item: str = "") -> JsxElement {
    nav = useNavigate();
    [requests, set_requests] = useState(None);
    [categories, set_categories] = useState([]);
    [writing, set_writing] = useState(False);
    [category, set_category] = useState("");
    [problem, set_problem] = useState("");
    base = section_path(slug, "help");

    async def load {
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await support_requests(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("support_requests failed", e);
        }
        if answer is None {
            set_problem(OFFLINE);
            return;
        }
        if not answer["ok"] {
            set_problem(answer["error"]["message"]);
            return;
        }
        set_problem("");
        set_requests(answer["requests"]);
        set_categories(answer["categories"]);
    }

    def start {
        load();
    }
    useEffect(start, [slug, shift_open]);
    # New messages without a refresh: a chat every few seconds, the list less often.
    use_every(CHAT_MS if item else LIST_MS, load, [slug, shift_open, item]);

    def changed(updated: dict[str, any]) {  # jac:ignore[W1037]
        listed: list[dict[str, any]] = requests or [];  # jac:ignore[W1037]
        others = [
            r
            for r in listed
            if r["request_id"] != updated["request_id"]
        ];
        set_requests([updated] + others);
    }

    async def ask(text: str) -> bool {
        if not category {
            set_problem("Choose what it's about.");
            return False;
        }
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await ask_for_help(slug, category, text);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("ask_for_help failed", e);
        }
        if answer is None {
            set_problem(OFFLINE);
            return False;
        }
        if not answer["ok"] {
            set_problem(answer["error"]["message"]);
            return False;
        }
        set_problem("");
        set_writing(False);
        set_category("");
        changed(answer["request"]);
        nav(f"{base}/{answer['request']['request_id']}");
        return True;
    }

    async def reply(text: str) -> bool {
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await reply_to_support(slug, item, text);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("reply_to_support failed", e);
        }
        if answer is None {
            set_problem(OFFLINE);
            return False;
        }
        if not answer["ok"] {
            set_problem(answer["error"]["message"]);
            return False;
        }
        set_problem("");
        changed(answer["request"]);
        return True;
    }

    # An open chat with messages we haven't read: mark it read, and clear the count.
    opened: list[dict[str, any]] = [  # jac:ignore[W1037]
        r
        for r in (requests or [])
        if r["request_id"] == item
    ];
    unread_here: int = opened[0]["unread"] if item and opened else 0;
    async def read_it {
        if not unread_here {
            return;
        }
        try {
            answer: any = await support_seen(slug, item);  # jac:ignore[W1037,W2037]
            if answer["ok"] {
                changed(answer["request"]);
                seen_now();
            }
        } except Exception as e {
            console.warn("support_seen failed", e);
        }
    }
    def mark_read {
        read_it();
    }
    useEffect(mark_read, [item, unread_here]);

    alert = problem
        and <Alert variant="destructive" role="alert">
            <AlertDescription>{problem}</AlertDescription>
        </Alert>;
    if requests is None {
        return alert
            or <p
                role="status"
                className="flex items-center gap-2 text-muted-foreground"
            >
                <Spinner aria-hidden="true"/>
                Loading your requests…
            </p>;
    }
    listed: list[dict[str, any]] = requests;  # jac:ignore[W1037]
    if item {
        found = [
            r
            for r in listed
            if r["request_id"] == item
        ];
        if not found {
            return
                <div className="flex flex-col gap-4">
                    <AppLink
                        to={base}
                        className="inline-flex min-h-11 items-center text-sm font-medium"
                    >
                        ← All requests
                    </AppLink>
                    <p className="text-muted-foreground">That request isn't here.</p>
                </div>;
        }
        chat: dict[str, any] = found[0];  # jac:ignore[W1037]
        return
            <div
                className="flex max-w-2xl flex-col gap-3 rounded-xl bg-card p-3 ring-1 ring-foreground/10 sm:p-4"
                data-testid="help-chat"
            >
                <div className="flex items-center justify-between gap-2 border-b pb-3">
                    <AppLink
                        to={base}
                        className="inline-flex min-h-11 items-center text-sm font-medium"
                    >
                        ← All requests
                    </AppLink>
                    <Badge variant="outline" data-testid="help-status">
                        {chat["status_label"]}
                    </Badge>
                </div>
                <h2 className="font-semibold">{chat["category_label"]}</h2>
                <SupportThread messages={chat["messages"]} reader="cinema"/>
                {alert}
                <div className="sticky bottom-0 border-t bg-card pt-3">
                    <ChatComposer field_id="help-reply" label="Reply" on_send={reply}/>
                </div>
            </div>;
    }
    choices: list[dict[str, str]] = categories;
    return
        <div className="flex max-w-2xl flex-col gap-4" data-testid="help-section">
            <div className="flex flex-wrap items-center justify-between gap-3">
                <p className="text-sm text-muted-foreground">
                    Something not working? Tell AfriCinemas and we'll answer here.
                </p>
                {not writing
                    and <Button
                        className="min-h-11 px-4"
                        onClick={lambda { set_writing(True); }}
                        data-testid="help-new"
                    >
                        <HugeiconsIcon
                            icon={Add01Icon}
                            strokeWidth={2}
                            aria-hidden="true"
                        />
                        New request
                    </Button>}
            </div>
            {writing
                and <section
                    data-testid="help-form"
                    className="flex flex-col gap-3 rounded-xl bg-card p-4 ring-1 ring-foreground/10"
                >
                    <div className="flex flex-col gap-1.5">
                        <Label htmlFor="help-category">What's it about</Label>
                        <select
                            id="help-category"
                            value={category}
                            onChange={on_input(set_category)}
                            className={SELECT_CLASSES}
                        >
                            <option value="">Choose…</option>
                            {[
                                <option key={c["key"]} value={c["key"]}>
                                    {c["label"]}
                                </option> for c in choices
                            ]}
                        </select>
                    </div>
                    {alert}
                    <ChatComposer
                        field_id="help-text"
                        label="What's happening"
                        placeholder="What's happening?"
                        on_send={ask}
                        hint={PRIVATE_HINT}
                    />
                    <Button
                        variant="ghost"
                        className="min-h-11 w-fit px-3"
                        onClick={lambda {
                            set_writing(False);
                            set_problem("");
                        }}
                    >
                        Cancel
                    </Button>
                </section>}
            {not writing and alert}
            {len(listed) == 0
                and not writing
                and <p className="text-sm text-muted-foreground">No requests yet.</p>}
            {len(listed) > 0
                and <ul
                    className="flex flex-col divide-y rounded-xl bg-card ring-1 ring-foreground/10"
                    aria-label="Your requests, newest first"
                >
                    {[
                        <li key={r["request_id"]} data-testid="help-request">
                            <AppLink
                                to={f"{base}/{r['request_id']}"}
                                className="flex min-h-11 flex-col gap-1 p-4 hover:bg-muted"
                            >
                                <span
                                    className="flex flex-wrap items-center justify-between gap-2"
                                >
                                    <span
                                        className={"flex items-center gap-2 "
                                            + (
                                                "font-semibold"
                                                    if r["unread"]
                                                    else "font-medium"
                                            )}
                                    >
                                        {r["category_label"]}{r["unread"]
                                            and <span
                                                className="rounded-full bg-primary px-2 text-xs font-semibold text-primary-foreground tabular-nums"
                                                data-testid="help-unread"
                                            >
                                                {r["unread"]}
                                                <span className="sr-only"> unread</span>
                                            </span>}
                                    </span>
                                    <span className="text-xs text-muted-foreground">
                                        {when(r["updated_at"])}
                                    </span>
                                </span>
                                <span
                                    className="flex items-center justify-between gap-3"
                                >
                                    <span
                                        className="line-clamp-1 min-w-0 break-all text-sm text-muted-foreground"
                                    >
                                        {last_text(r)}
                                    </span>
                                    <Badge
                                        variant="outline"
                                        className="shrink-0"
                                        data-testid="help-status"
                                    >
                                        {r["status_label"]}
                                    </Badge>
                                </span>
                            </AppLink>
                        </li> for r in listed
                    ]}
                </ul>}
        </div>;
}
