"""Reviews in the platform console (P14.5, ADR-0071): `/reviews` and `/reviews/<slug>`.

For reviewers and super admins. The queue lists the cinemas waiting, oldest first. A
cinema's review shows the owner's and the business's details beside the files they
sent (each opened here: an ID photo as an image, a certificate as a PDF), and the
checklist; every item must be ticked to approve. Asking for changes or rejecting needs
reasons, one a line, which the owner reads on their Verification page and by email.

use_waiting_reviews gives the console's nav its count, asked every LIST_MS.
"""

import from react { useState, useEffect }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.badge { Badge }
import from ...components.ui.button { Button }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from ...components.ui.textarea { Textarea }
import from core.platform.review_api {
    platform_reviews,  # jac:ignore[W2037] authenticated endpoint
    platform_review,  # jac:ignore[W2037]
    platform_review_file,  # jac:ignore[W2037]
    platform_decide  # jac:ignore[W2037]
}
import from ..shell.AppLink { AppLink }
import from ..backoffice.form_parts { on_input }
import from ..storefront.DocumentPage { OpenPdf }
import from ..support.live { use_every, LIST_MS }

glob OFFLINE: str = "We couldn't reach the server. Check your connection and try again.",
     STATUS_LABELS: dict[str, str] = {
         "draft": "Not submitted",
         "submitted": "Waiting for review",
         "approved": "Approved",
         "changes_requested": "Changes asked",
         "rejected": "Rejected"
     };

def:pub use_waiting_reviews(enabled: bool) -> int {
    # How many cinemas wait for a review, for the nav's count.
    [count, set_count] = useState(0);
    async def ask {
        if not enabled {
            return;
        }
        try {
            answer: any = await platform_reviews();  # jac:ignore[W1037,W2037]
            if answer["ok"] {
                set_count(len(answer["reviews"]));
            }
        } except Exception as e {
            console.warn("platform_reviews failed", e);
        }
    }
    use_every(LIST_MS, ask, [enabled]);
    return count;
}

def:pub ReviewQueue -> JsxElement {
    [rows, set_rows] = useState(None);
    [problem, set_problem] = useState("");
    async def load {
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await platform_reviews();  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("platform_reviews failed", e);
        }
        if answer is None {
            set_problem(OFFLINE);
        } elif not answer["ok"] {
            set_problem(answer["error"]["message"]);
        } else {
            set_rows(answer["reviews"]);
        }
    }
    def start {
        load();
    }
    useEffect(start, []);
    if problem {
        return
            <Alert variant="destructive" role="alert">
                <AlertDescription>{problem}</AlertDescription>
            </Alert>;
    }
    if rows is None {
        return
            <p role="status" className="flex items-center gap-2 text-muted-foreground">
                <Spinner aria-hidden="true"/>
                Loading…
            </p>;
    }
    waiting: list[dict[str, str]] = rows;
    return
        <div className="flex max-w-3xl flex-col gap-4" data-testid="review-queue">
            <p className="text-sm text-muted-foreground">
                Cinemas that sent their details and documents, oldest first. Each stays private until it's approved.
            </p>
            {len(waiting) == 0
                and <p
                    className="rounded-lg border bg-card p-4 text-sm"
                    data-testid="no-reviews"
                >
                    Nothing to review.
                </p>}
            <ul
                className="flex flex-col divide-y rounded-lg border bg-card empty:hidden"
            >
                {[
                    <li key={r["slug"]}>
                        <AppLink
                            to={f"/reviews/{r['slug']}"}
                            testid="review-row"
                            className="flex min-h-14 flex-wrap items-center justify-between gap-2 px-4 py-3 hover:bg-muted/50"
                        >
                            <span className="flex flex-col">
                                <span className="font-medium">{r["name"]}</span>
                                <span className="text-sm text-muted-foreground">
                                    {r["registered_name"]}
                                </span>
                            </span>
                            <span className="text-sm text-muted-foreground">
                                {f"Sent {(r['submitted_at'] or '')[:10]}"}
                            </span>
                        </AppLink>
                    </li> for r in waiting
                ]}
            </ul>
        </div>;
}

def FileView(slug: str, file: dict[str, str]) -> JsxElement {
    # One file: Open loads it here (each look is logged).
    [loaded, set_loaded] = useState(None);
    [busy, set_busy] = useState(False);
    [problem, set_problem] = useState("");
    async def open_it {
        set_busy(True);
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await platform_review_file(slug, file["item"]);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("platform_review_file failed", e);
        }
        set_busy(False);
        if answer is None or not answer["ok"] {
            set_problem(answer["error"]["message"] if answer is not None else OFFLINE);
            return;
        }
        set_loaded(answer);
    }
    shown: dict[str, str] | None = loaded;
    return
        <li className="flex flex-col gap-2 p-4" data-testid="review-file">
            <div className="flex flex-wrap items-center justify-between gap-2">
                <span className="font-medium">{file["label"]}</span>
                {(
                    <Button
                        type="button"
                        variant="outline"
                        className="min-h-11 px-4"
                        disabled={busy}
                        data-testid={f"open-{file['item']}"}
                        onClick={lambda { open_it(); }}
                    >
                        {busy and <Spinner aria-hidden="true"/>}Open
                    </Button>
                )
                    if file["type"] and shown is None
                    else (
                        <span
                            className="text-sm text-muted-foreground"
                            data-testid={f"file-state-{file['item']}"}
                        >
                            {f"Deleted {file['removed_at'][:10]}, as our retention rules say"
                                if file["removed_at"]
                                else "Not sent"}
                        </span>
                            if not file["type"]
                            else <span className="hidden"/>
                    )}
            </div>
            {problem
                and <p role="alert" className="text-sm text-destructive">{problem}</p>}
            {shown is not None
                and shown["type"] == "image"
                and <img
                    src={f"data:image/webp;base64,{shown['file']}"}
                    alt={file["label"]}
                    className="max-h-[32rem] w-full rounded-md border object-contain"
                    data-testid={f"shown-{file['item']}"}
                />}
            {shown is not None
                and shown["type"] == "pdf"
                and <OpenPdf pdf={shown["file"]} title={file["label"]}/>}
        </li>;
}

def:pub ReviewPage(slug: str) -> JsxElement {
    [found, set_found] = useState(None);
    [problem, set_problem] = useState("");
    [ticked, set_ticked] = useState([]);
    [reasons, set_reasons] = useState("");
    [busy, set_busy] = useState("");
    [message, set_message] = useState("");

    def seen(answer: any) {  # jac:ignore[W1037]
        set_found(answer);
    }
    async def load {
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await platform_review(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("platform_review failed", e);
        }
        if answer is None {
            set_problem(OFFLINE);
        } elif not answer["ok"] {
            set_problem(answer["error"]["message"]);
        } else {
            set_problem("");
            seen(answer);
        }
    }
    def start {
        load();
    }
    useEffect(start, [slug]);

    def tick(n: int) {
        done: list[int] = ticked;
        set_ticked(
            [
                i
                for i in done
                if i != n
            ]
                if n in done
                else [*done, n]
        );
    }

    async def decide(decision: str) {
        set_busy(decision);
        set_message("");
        said = [
            line.strip()
            for line in reasons.split("\n")
            if line.strip()
        ];
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await platform_decide(slug, decision, said);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("platform_decide failed", e);
        }
        set_busy("");
        if answer is None {
            set_problem(OFFLINE);
            return;
        }
        if not answer["ok"] {
            set_message(answer["error"]["message"]);
            return;
        }
        seen(answer);
        set_message(
            {
                "approve": "Approved: the cinema is public now, and its owner is emailed.",
                "changes": "Sent: the owner is emailed, and their page shows what to change.",
                "reject": "Rejected: the owner is emailed, and the cinema stays private."
            }[decision]
        );
    }

    back = <AppLink
        to="/reviews"
        className="inline-flex min-h-11 w-fit items-center text-sm font-medium underline-offset-4 hover:underline"
    >
        ← All reviews
    </AppLink>;
    if problem {
        return
            <div className="flex max-w-3xl flex-col gap-4">
                {back}
                <Alert variant="destructive" role="alert">
                    <AlertDescription>{problem}</AlertDescription>
                </Alert>
            </div>;
    }
    if found is None {
        return
            <p role="status" className="flex items-center gap-2 text-muted-foreground">
                <Spinner aria-hidden="true"/>
                Loading the review…
            </p>;
    }
    page: dict[str, any] = found;  # jac:ignore[W1037]
    details: dict[str, str] = page["details"];
    labels: dict[str, str] = page["labels"];
    files: list[dict[str, str]] = page["files"];
    checks: list[str] = page["checklist"];
    done: list[int] = ticked;
    waiting: bool = page["status"] == "submitted";
    rows = [
        (labels["legal_name"], details.get("legal_name", "")),
        (labels["id_number"], details.get("id_number", "")),
        ("Phone", details.get("phone", "")),
        (labels["registered_name"], details.get("registered_name", "")),
        ("Type of business", page["business_type"]),
        (labels["registration_number"], details.get("registration_number", "")),
        ("KRA PIN", details.get("kra_pin", "")),
        ("County permit expires", details.get("permit_expiry", "")),
        (labels["premises_address"], details.get("premises_address", "")),
        ("Owner's email", ", ".join(page["owners"]))
    ];
    return
        <div className="flex max-w-5xl flex-col gap-6" data-testid="review-page">
            {back}
            <section className="flex flex-col gap-2">
                <h2 className="break-words text-2xl font-semibold">
                    {page["cinema"]["name"]}
                </h2>
                <p
                    className="flex flex-wrap items-center gap-2 text-sm text-muted-foreground"
                >
                    <Badge variant="outline" data-testid="review-status">
                        {STATUS_LABELS.get(page["status"], page["status"])}
                    </Badge>
                    <span>{f"Sent {(page['submitted_at'] or '')[:10]}"}</span>
                    {page["reviewed_by"]
                        and <span>{f"Last decided by {page['reviewed_by']}"}</span>}
                </p>
            </section>
            <div className="grid gap-6 lg:grid-cols-2">
                <section className="flex flex-col gap-2 rounded-lg border bg-card p-4">
                    <h3 className="font-semibold">What they told us</h3>
                    <dl
                        className="grid gap-x-4 gap-y-2 text-sm sm:grid-cols-[auto_1fr]"
                    >
                        {[
                            <div key={label} className="contents">
                                <dt className="text-muted-foreground">{label}</dt>
                                <dd className="break-words font-medium">
                                    {value or "—"}
                                </dd>
                            </div> for (label, value) in rows
                        ]}
                    </dl>
                </section>
                <section className="flex flex-col rounded-lg border bg-card">
                    <h3 className="px-4 pt-4 font-semibold">What they sent</h3>
                    <p className="px-4 text-sm text-muted-foreground">
                        Opening a file is recorded in the platform's audit log.
                    </p>
                    <ul className="flex flex-col divide-y">
                        {[
                            <FileView key={f["item"]} slug={slug} file={f}/>
                            for f in files
                        ]}
                    </ul>
                </section>
            </div>
            {waiting
                and <section
                    className="flex flex-col gap-4 rounded-lg border bg-card p-4"
                    data-testid="review-decision"
                >
                    <fieldset className="flex flex-col gap-1">
                        <legend className="pb-1 font-semibold">
                            Check before approving
                        </legend>
                        {[
                            <label
                                key={f"{n}"}
                                className="flex min-h-11 cursor-pointer items-center gap-3 text-sm"
                            >
                                <input
                                    type="checkbox"
                                    className="size-5"
                                    checked={n in done}
                                    data-testid="review-check"
                                    onChange={lambda { tick(n); }}
                                />
                                {c}
                            </label> for (n, c) in enumerate(checks)
                        ]}
                    </fieldset>
                    <div className="flex flex-col gap-1.5">
                        <Label htmlFor="review-reasons">
                            What to change, or why it's refused
                        </Label>
                        <Textarea
                            id="review-reasons"
                            value={reasons}
                            rows={4}
                            aria-describedby="review-reasons-help"
                            onChange={on_input(lambda (v: str) { set_reasons(v); })}
                        />
                        <p
                            id="review-reasons-help"
                            className="text-sm text-muted-foreground"
                        >
                            One a line. The owner reads them on their Verification page and by email.
                        </p>
                    </div>
                    {message and <p role="alert" className="text-sm">{message}</p>}
                    <div className="flex flex-wrap gap-2">
                        <Button
                            type="button"
                            className="min-h-11 px-5"
                            disabled={busy != "" or len(done) < len(checks)}
                            data-testid="approve-verification"
                            onClick={lambda { decide("approve"); }}
                        >
                            {busy == "approve" and <Spinner aria-hidden="true"/>}Approve
                        </Button>
                        <Button
                            type="button"
                            variant="outline"
                            className="min-h-11 px-5"
                            disabled={busy != "" or not reasons.strip()}
                            data-testid="ask-changes"
                            onClick={lambda { decide("changes"); }}
                        >
                            {busy == "changes"
                                and <Spinner aria-hidden="true"/>}Ask for changes
                        </Button>
                        <Button
                            type="button"
                            variant="destructive"
                            className="min-h-11 px-5"
                            disabled={busy != "" or not reasons.strip()}
                            data-testid="reject-verification"
                            onClick={lambda { decide("reject"); }}
                        >
                            {busy == "reject" and <Spinner aria-hidden="true"/>}Reject
                        </Button>
                    </div>
                </section>}
            {not waiting
                and message
                and <p role="status" className="text-sm" data-testid="review-done">
                    {message}
                </p>}
            {not waiting
                and len(page["reasons"]) > 0
                and <section
                    className="flex flex-col gap-1 rounded-lg border bg-card p-4"
                >
                    <h3 className="font-semibold">Reasons given</h3>
                    <ul className="list-disc pl-5 text-sm">
                        {[
                            <li key={f"{i}"}>{r}</li>
                            for (i, r) in enumerate(page["reasons"])
                        ]}
                    </ul>
                </section>}
        </div>;
}
