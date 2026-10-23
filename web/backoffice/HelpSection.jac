"""`/app/:slug/help`: asking AfriCinemas for technical help (P13.5a).

For staff with support.request (owners, tenant admins, general and finance managers).
A form (what it's about, what's happening) sends a request, and every request of the
cinema is listed newest first: its status, its messages, and a box to reply. Our
replies appear here, and the status says whose turn it is. The server checks every
request (core/support/requests.jac).
"""

import from react { useState, useEffect }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.badge { Badge }
import from ...components.ui.button { Button }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.support.requests {
    ask_for_help,  # jac:ignore[W2037] authenticated endpoint
    support_requests,  # jac:ignore[W2037]
    reply_to_support  # jac:ignore[W2037]
}
import from .form_parts { TextField, on_input, submit_with }
import from ..support.SupportThread { SupportThread }

glob OFFLINE: str = "We couldn't reach AfriCinemas. Check your connection and try again.",
     SELECT_CLASSES: str = "min-h-11 rounded-md border border-input bg-background px-3 text-sm",
     PRIVATE_HINT: str = "Never include passwords, PINs or card numbers.";

def RequestCard(
    slug: str,
    request: dict[str, any],  # jac:ignore[W1037]
    on_changed: any  # jac:ignore[W1037]
) -> JsxElement {
    [text, set_text] = useState("");
    [busy, set_busy] = useState(False);
    [problem, set_problem] = useState("");
    async def send {
        if not text.strip() {
            set_problem("Write your reply first.");
            return;
        }
        set_busy(True);
        set_problem("");
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await reply_to_support(slug, request["request_id"], text);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("reply_to_support failed", e);
        }
        set_busy(False);
        if answer is None {
            set_problem(OFFLINE);
        } elif not answer["ok"] {
            set_problem(answer["error"]["message"]);
        } else {
            set_text("");
            on_changed(answer["request"]);
        }
    }
    field_id = f"reply-{request['request_id']}";
    return
        <li
            data-testid="help-request"
            className="flex flex-col gap-3 rounded-lg border bg-card p-4"
        >
            <div className="flex flex-wrap items-center justify-between gap-2">
                <h3 className="font-semibold">{request["category_label"]}</h3>
                <Badge variant="outline" data-testid="help-status">
                    {request["status_label"]}
                </Badge>
            </div>
            <SupportThread messages={request["messages"]} reader="cinema"/>
            <form
                className="flex flex-col gap-2"
                onSubmit={submit_with(lambda { send(); })}
            >
                <TextField
                    field_id={field_id}
                    label="Reply"
                    value={text}
                    on_value={set_text}
                    multiline={True}
                    error={problem}
                />
                <Button
                    type="submit"
                    variant="outline"
                    className="min-h-11 w-fit px-4"
                    disabled={busy}
                >
                    {busy and <Spinner aria-hidden="true"/>}Send reply
                </Button>
            </form>
        </li>;
}

def:pub HelpSection(slug: str, shift_open: bool = True) -> JsxElement {
    [requests, set_requests] = useState(None);
    [categories, set_categories] = useState([]);
    [category, set_category] = useState("");
    [text, set_text] = useState("");
    [busy, set_busy] = useState(False);
    [problem, set_problem] = useState("");
    [sent, set_sent] = useState(False);

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

    async def ask {
        if not category {
            set_problem("Choose what it's about.");
            return;
        }
        if not text.strip() {
            set_problem("Write what's happening.");
            return;
        }
        set_busy(True);
        set_problem("");
        set_sent(False);
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await ask_for_help(slug, category, text);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("ask_for_help failed", e);
        }
        set_busy(False);
        if answer is None {
            set_problem(OFFLINE);
        } elif not answer["ok"] {
            set_problem(answer["error"]["message"]);
        } else {
            set_text("");
            set_category("");
            set_sent(True);
            listed: list[dict[str, any]] = requests or [];  # jac:ignore[W1037]
            set_requests([answer["request"]] + listed);
        }
    }

    def changed(updated: dict[str, any]) {  # jac:ignore[W1037]
        listed: list[dict[str, any]] = requests or [];  # jac:ignore[W1037]
        set_requests(
            [updated if r["request_id"] == updated["request_id"] else r for r in listed]
        );
    }

    if requests is None and not problem {
        return
            <p role="status" className="flex items-center gap-2 text-muted-foreground">
                <Spinner aria-hidden="true"/>
                Loading your requests…
            </p>;
    }
    listed: list[dict[str, any]] = requests or [];  # jac:ignore[W1037]
    choices: list[dict[str, str]] = categories;
    return
        <div className="flex max-w-3xl flex-col gap-6" data-testid="help-section">
            <p className="text-sm text-muted-foreground">
                Something not working? Tell AfriCinemas and we'll answer here.
            </p>
            <form
                data-testid="help-form"
                className="flex flex-col gap-3 rounded-lg border bg-card p-4"
                onSubmit={submit_with(lambda { ask(); })}
            >
                <h2 className="text-lg font-semibold">Ask for help</h2>
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
                <TextField
                    field_id="help-text"
                    label="What's happening"
                    value={text}
                    on_value={set_text}
                    multiline={True}
                    hint={PRIVATE_HINT}
                />
                {problem
                    and <Alert variant="destructive" role="alert">
                        <AlertDescription>{problem}</AlertDescription>
                    </Alert>}
                <p
                    role="status"
                    aria-live="polite"
                    className="text-sm empty:hidden"
                    data-testid="help-sent"
                >
                    {"Sent. We'll answer here." if sent else ""}
                </p>
                <Button type="submit" className="min-h-11 w-fit px-5" disabled={busy}>
                    {busy and <Spinner aria-hidden="true"/>}Send to AfriCinemas
                </Button>
            </form>
            {len(listed) > 0
                and <section className="flex flex-col gap-3">
                    <h2 className="text-lg font-semibold">Your requests</h2>
                    <ul className="flex flex-col gap-3">
                        {[
                            <RequestCard
                                key={r["request_id"]}
                                slug={slug}
                                request={r}
                                on_changed={changed}
                            /> for r in listed
                        ]}
                    </ul>
                </section>}
        </div>;
}
