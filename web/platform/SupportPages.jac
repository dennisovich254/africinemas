"""The platform console's Support section (P13.5a): cinemas' help requests.

`/support`: every cinema's requests, newest first, one status at a time (Open, the ones
waiting on us, is the first; Waiting for the cinema; Closed), each with its count.
`/support/<id>`: a request's thread, a reply box (a reply hands it to the cinema), and
Close or Reopen. For platform support staff (platform.support); the server checks
every request (core/support/requests.jac).
"""

import from react { useState, useEffect }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.badge { Badge }
import from ...components.ui.button { Button }
import from ...components.ui.spinner { Spinner }
import from core.support.requests {
    platform_support_requests,  # jac:ignore[W2037] authenticated endpoint
    platform_support_request,  # jac:ignore[W2037]
    platform_support_reply,  # jac:ignore[W2037]
    platform_support_status  # jac:ignore[W2037]
}
import from ..shell.AppLink { AppLink }
import from ..backoffice.form_parts { TextField, submit_with }
import from ..support.SupportThread { SupportThread, when }

glob OFFLINE: str = "We couldn't reach the server. Check your connection and try again.";

def:pub SupportInbox -> JsxElement {
    [status, set_status] = useState("open");
    [found, set_found] = useState(None);
    [problem, set_problem] = useState("");

    async def load(chosen: str) {
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await platform_support_requests(chosen);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("platform_support_requests failed", e);
        }
        if answer is None {
            set_problem(OFFLINE);
        } elif not answer["ok"] {
            set_problem(answer["error"]["message"]);
        } else {
            set_problem("");
            set_found(answer);
        }
    }

    def start {
        load(status);
    }
    useEffect(start, [status]);

    if problem {
        return
            <Alert variant="destructive" role="alert">
                <AlertDescription>{problem}</AlertDescription>
            </Alert>;
    }
    if found is None {
        return
            <p role="status" className="flex items-center gap-2 text-muted-foreground">
                <Spinner aria-hidden="true"/>
                Loading requests…
            </p>;
    }
    shown: dict[str, any] = found;  # jac:ignore[W1037]
    counts: list[dict[str, any]] = shown["counts"];  # jac:ignore[W1037]
    rows: list[dict[str, any]] = shown["requests"];  # jac:ignore[W1037]
    return
        <div className="flex max-w-4xl flex-col gap-4" data-testid="support-inbox">
            <div
                role="tablist"
                aria-label="Requests by status"
                className="flex flex-wrap gap-2"
            >
                {[
                    <Button
                        key={c["key"]}
                        type="button"
                        role="tab"
                        aria-selected={"true" if c["key"] == status else "false"}
                        variant={"default" if c["key"] == status else "outline"}
                        className="min-h-11 px-4"
                        data-testid={f"support-tab-{c['key']}"}
                        onClick={lambda { set_status(c["key"]); }}
                    >
                        {f"{c['label']} ({c['count']})"}
                    </Button> for c in counts
                ]}
            </div>
            {len(rows) == 0
                and <p
                    className="text-sm text-muted-foreground"
                    data-testid="support-empty"
                >
                    Nothing here.
                </p>}
            {len(rows) > 0
                and <ul className="flex flex-col divide-y rounded-lg border bg-card">
                    {[
                        <li key={r["request_id"]} data-testid="support-row">
                            <AppLink
                                to={f"/support/{r['request_id']}"}
                                className="flex min-h-11 flex-col gap-1 p-4 hover:bg-muted"
                            >
                                <span
                                    className="flex flex-wrap items-baseline justify-between gap-2"
                                >
                                    <span className="font-medium">
                                        {f"{r['cinema']} · {r['category_label']}"}
                                    </span>
                                    <span className="text-sm text-muted-foreground">
                                        {when(r["updated_at"])}
                                    </span>
                                </span>
                                <span
                                    className="line-clamp-2 break-words text-sm text-muted-foreground"
                                >
                                    {r["messages"][len(r["messages"]) - 1]["text"]}
                                </span>
                            </AppLink>
                        </li> for r in rows
                    ]}
                </ul>}
        </div>;
}

def:pub SupportRequestPage(request_id: str) -> JsxElement {
    [found, set_found] = useState(None);
    [problem, set_problem] = useState("");
    [text, set_text] = useState("");
    [busy, set_busy] = useState(False);
    [message, set_message] = useState("");

    async def run(work: any, done: str) -> bool {  # jac:ignore[W1037]
        set_busy(True);
        set_message("");
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await work();
        } except Exception as e {
            console.warn("support request failed", e);
        }
        set_busy(False);
        if answer is None {
            set_problem(OFFLINE);
            return False;
        }
        if not answer["ok"] {
            set_problem(answer["error"]["message"]);
            return False;
        }
        set_problem("");
        set_found(answer["request"]);
        set_message(done);
        return True;
    }

    def start {
        run(lambda -> any { return platform_support_request(request_id); }, "");  # jac:ignore[W1037,W2037]
    }
    useEffect(start, [request_id]);

    async def send {
        wanted: str = text;
        if not wanted.strip() {
            set_problem("Write your reply first.");
            return;
        }
        if await run(
            lambda -> any { return platform_support_reply(request_id, wanted); },  # jac:ignore[W1037,W2037]
            "Sent. It's waiting for the cinema now."
        ) {
            set_text("");
        }
    }

    async def set_to(status: str, done: str) {
        await run(
            lambda -> any { return platform_support_status(request_id, status); },  # jac:ignore[W1037,W2037]
            done
        );
    }

    back = <AppLink
        to="/support"
        className="inline-flex min-h-11 w-fit items-center text-sm font-medium underline-offset-4 hover:underline"
    >
        ← All requests
    </AppLink>;
    if found is None {
        return
            <div className="flex max-w-3xl flex-col gap-4">
                {back}{problem
                    and <Alert variant="destructive" role="alert">
                        <AlertDescription>{problem}</AlertDescription>
                    </Alert>}{not problem
                    and <p
                        role="status"
                        className="flex items-center gap-2 text-muted-foreground"
                    >
                        <Spinner aria-hidden="true"/>
                        Loading the request…
                    </p>}
            </div>;
    }
    request: dict[str, any] = found;  # jac:ignore[W1037]
    closed = request["status"] == "closed";
    return
        <div className="flex max-w-3xl flex-col gap-4" data-testid="support-request">
            {back}
            <section className="flex flex-col gap-1">
                <h2 className="break-words text-xl font-semibold">
                    {f"{request['cinema']} · {request['category_label']}"}
                </h2>
                <p
                    className="flex flex-wrap items-center gap-2 text-sm text-muted-foreground"
                >
                    <Badge variant="outline" data-testid="support-status">
                        {request["status_label"]}
                    </Badge>
                    <AppLink
                        to={f"/cinemas/{request['cinema_slug']}"}
                        className="inline-flex min-h-11 items-center underline underline-offset-4"
                    >
                        The cinema's page
                    </AppLink>
                </p>
            </section>
            <SupportThread
                messages={request["messages"]}
                reader="africinemas"
                cinema={request["cinema"]}
            />
            <p
                role="status"
                aria-live="polite"
                className="text-sm empty:hidden"
                data-testid="support-message-sent"
            >
                {message}
            </p>
            {problem
                and <Alert variant="destructive" role="alert">
                    <AlertDescription>{problem}</AlertDescription>
                </Alert>}
            <form
                className="flex flex-col gap-2 rounded-lg border bg-card p-4"
                data-testid="support-reply"
                onSubmit={submit_with(lambda { send(); })}
            >
                <TextField
                    field_id="support-reply-text"
                    label="Reply to the cinema"
                    value={text}
                    on_value={set_text}
                    multiline={True}
                />
                <div className="flex flex-wrap gap-2">
                    <Button type="submit" className="min-h-11 px-5" disabled={busy}>
                        {busy and <Spinner aria-hidden="true"/>}Send reply
                    </Button>
                    {not closed
                        and <Button
                            type="button"
                            variant="outline"
                            className="min-h-11 px-4"
                            disabled={busy}
                            onClick={lambda { set_to("closed", "Closed."); }}
                        >
                            Close request
                        </Button>}
                    {closed
                        and <Button
                            type="button"
                            variant="outline"
                            className="min-h-11 px-4"
                            disabled={busy}
                            onClick={lambda { set_to("open", "Reopened."); }}
                        >
                            Reopen
                        </Button>}
                </div>
            </form>
        </div>;
}
