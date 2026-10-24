"""Settings -> Policies (P14.3b, ADR-0067): the cinema's policy pages.

Six policies, each written here and linked from every storefront footer once
published: terms of ticket sale, privacy, refunds and cancellations, house rules,
accessibility and the KFCB age ratings. Terms, privacy and refunds are required before
the cinema can be submitted for review (14.4). Each can start from our plain-language
template, filled in with the cinema's name and contact; publishing asks the writer to
tick that they've read it and it's right for their cinema. The preview is drawn as
the storefront draws it (PolicyText).
"""

import from react { useState, useEffect }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.badge { Badge }
import from ...components.ui.button { Button }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from ...components.ui.textarea { Textarea }
import from core.catalog.policies {
    policies,  # jac:ignore[W2037] authenticated endpoint
    save_policy,  # jac:ignore[W2037]
    upload_policy_pdf,  # jac:ignore[W2037]
    remove_policy_pdf  # jac:ignore[W2037]
}
import from ..storefront.PolicyPage { PolicyText }
import from .form_parts { on_input, read_as_base64 }

def status_of(p: dict[str, any]) -> str {  # jac:ignore[W1037]
    if p["published"] {
        return "Published";
    }
    return "Draft" if p["text"] or p["has_pdf"] else "Not written";
}

def:pub PoliciesSection(slug: str) -> JsxElement {
    [listed, set_listed] = useState(None);
    [open_kind, set_open_kind] = useState("");
    [text, set_text] = useState("");
    [reviewed, set_reviewed] = useState(False);
    [busy, set_busy] = useState("");
    [message, set_message] = useState("");
    [failed, set_failed] = useState("");

    async def load {
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await policies(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("policies failed", e);
        }
        if answer is None {
            set_failed("We couldn't load this. Refresh the page to try again.");
        } elif not answer["ok"] {
            set_failed(answer["error"]["message"]);
        } else {
            set_failed("");
            set_listed(answer["policies"]);
        }
    }
    def start {
        load();
    }
    useEffect(start, [slug]);

    def choose(p: dict[str, any]) {  # jac:ignore[W1037]
        set_open_kind(p["kind"]);
        set_text(p["text"]);
        set_reviewed(False);
        set_message("");
        set_failed("");
    }

    async def change_pdf(kind: str, file: any) {  # jac:ignore[W1037]
        # Uploads `file` as the policy's PDF (P14.3d), or removes it when None.
        set_busy("pdf");
        set_message("");
        answer: any = None;  # jac:ignore[W1037]
        try {
            if file is None {
                answer = await remove_policy_pdf(slug, kind);  # jac:ignore[W2037]
            } else {
                encoded = await read_as_base64(file);
                answer = await upload_policy_pdf(slug, kind, encoded);  # jac:ignore[W2037]
            }
        } except Exception as e {
            console.warn("policy pdf failed", e);
        }
        set_busy("");
        if answer is None {
            set_failed(
                "We couldn't reach AfriCinemas. Check your connection and try again."
            );
            return;
        }
        if not answer["ok"] {
            set_failed(answer["error"]["message"]);
            return;
        }
        set_failed("");
        set_listed(answer["policies"]);
        set_message(
            "PDF removed."
                if file is None
                else "PDF added. Publish to show it on your storefront."
        );
    }

    async def save(kind: str, publish: bool) {
        set_busy("publish" if publish else "save");
        set_message("");
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await save_policy(slug, kind, text, publish, reviewed);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("save_policy failed", e);
        }
        set_busy("");
        if answer is None {
            set_failed(
                "We couldn't reach AfriCinemas. Check your connection and try again."
            );
            return;
        }
        if not answer["ok"] {
            set_failed(answer["error"]["message"]);
            return;
        }
        set_failed("");
        set_listed(answer["policies"]);
        set_reviewed(False);
        set_message(
            "Published. It's linked from your storefront's footer now."
                if publish
                else "Saved. Visitors don't see it until you publish it."
        );
    }

    if listed is None {
        if failed {
            return
                <Alert variant="destructive">
                    <AlertDescription>{failed}</AlertDescription>
                </Alert>;
        }
        return
            <p role="status" className="flex items-center gap-2 text-muted-foreground">
                <Spinner aria-hidden="true"/>
                Loading…
            </p>;
    }
    rows: list[dict[str, any]] = listed;  # jac:ignore[W1037]
    chosen = [
        p
        for p in rows
        if p["kind"] == open_kind
    ];
    current: dict[str, any] | None = chosen[0] if len(chosen) > 0 else None;  # jac:ignore[W1037]
    return
        <div data-testid="policies" className="flex max-w-3xl flex-col gap-6">
            <p className="text-sm text-muted-foreground">
                Each policy you publish is linked from the footer of every page of your storefront. Terms, privacy and refunds are needed before AfriCinemas can verify your cinema.
            </p>
            <ul className="flex flex-col divide-y rounded-lg border bg-card">
                {[
                    <li key={p["kind"]}>
                        <button
                            type="button"
                            data-testid={f"policy-{p['kind']}"}
                            aria-expanded={"true"
                                if p["kind"] == open_kind
                                else "false"}
                            onClick={lambda { choose(p); }}
                            className="flex min-h-14 w-full flex-wrap items-center justify-between gap-2 px-4 py-3 text-left hover:bg-muted/50"
                        >
                            <span
                                className="flex flex-wrap items-center gap-2 font-medium"
                            >
                                {p["title"]}{p["required"]
                                    and <Badge variant="outline">Required</Badge>}
                            </span>
                            <Badge
                                variant={"default" if p["published"] else "secondary"}
                                data-testid="policy-status"
                            >
                                {status_of(p)}
                            </Badge>
                        </button>
                    </li> for p in rows
                ]}
            </ul>
            {current is not None
                and <section
                    aria-labelledby="policy-editing"
                    data-testid="policy-editor"
                    className="flex flex-col gap-4 rounded-lg border bg-card p-4"
                >
                    <div className="flex flex-wrap items-center justify-between gap-2">
                        <h3 id="policy-editing" className="text-lg font-semibold">
                            {current["title"]}
                        </h3>
                        {not text
                            and <Button
                                type="button"
                                variant="outline"
                                className="min-h-11 px-4"
                                data-testid="use-template"
                                onClick={lambda { set_text(current["template"]); }}
                            >
                                Start from our template
                            </Button>}
                    </div>
                    <div className="flex flex-col gap-1.5">
                        <Label htmlFor="policy-text">Text</Label>
                        <Textarea
                            id="policy-text"
                            value={text}
                            rows={16}
                            aria-describedby="policy-format"
                            onChange={on_input(lambda (v: str) { set_text(v); })}
                        />
                        <p id="policy-format" className="text-sm text-muted-foreground">
                            Leave a blank line between paragraphs. Start a line with ## for a heading, or with - for a list item.
                        </p>
                    </div>
                    <div className="flex flex-col gap-1.5" data-testid="policy-pdf">
                        {(
                            <div className="flex flex-wrap items-center gap-2 text-sm">
                                <span>
                                    This policy also has a PDF, shown above its text.
                                </span>
                                <Button
                                    type="button"
                                    variant="outline"
                                    className="min-h-11 px-4"
                                    disabled={busy != ""}
                                    data-testid="remove-policy-pdf"
                                    onClick={lambda { change_pdf(
                                        current["kind"], None
                                    ); }}
                                >
                                    Remove the PDF
                                </Button>
                            </div>
                        )
                            if current["has_pdf"]
                            else <>
                                <Label htmlFor="policy-pdf-file">
                                    Or upload it as a PDF
                                </Label>
                                <input
                                    id="policy-pdf-file"
                                    type="file"
                                    accept="application/pdf,.pdf"
                                    className="min-h-11 text-sm"
                                    disabled={busy != ""}
                                    onChange={lambda (e: any) { if len(e.target.files)  # jac:ignore[W1037]
                                        > 0 {
                                        change_pdf(current["kind"], e.target.files[0]);
                                    }}}
                                />
                                <p className="text-sm text-muted-foreground">
                                    A PDF from your lawyer, up to 10 MB. Visitors can open it from the policy's page.
                                </p>
                            </>}
                    </div>
                    {text
                        and <details className="rounded-md border p-3">
                            <summary
                                className="min-h-11 cursor-pointer content-center font-medium"
                            >
                                Preview
                            </summary>
                            <div className="pt-3">
                                <PolicyText text={text}/>
                            </div>
                        </details>}
                    <label
                        className="flex min-h-11 cursor-pointer items-center gap-3 text-sm"
                    >
                        <input
                            type="checkbox"
                            id="policy-reviewed"
                            className="size-5"
                            checked={reviewed}
                            onChange={lambda { set_reviewed(not reviewed); }}
                        />
                        I've read this and it's right for my cinema. Our template is a starting point, not legal advice.
                    </label>
                    {failed
                        and <Alert variant="destructive" role="alert">
                            <AlertDescription>{failed}</AlertDescription>
                        </Alert>}
                    <p
                        role="status"
                        aria-live="polite"
                        className="text-sm empty:hidden"
                        data-testid="policy-saved"
                    >
                        {message}
                    </p>
                    <div className="flex flex-wrap gap-2">
                        <Button
                            type="button"
                            className="min-h-11 px-5"
                            disabled={busy != ""}
                            data-testid="publish-policy"
                            onClick={lambda { save(current["kind"], True); }}
                        >
                            {busy == "publish" and <Spinner aria-hidden="true"/>}{"Publish changes"
                                if current["published"]
                                else "Publish"}
                        </Button>
                        <Button
                            type="button"
                            variant="outline"
                            className="min-h-11 px-5"
                            disabled={busy != ""}
                            data-testid="save-policy"
                            onClick={lambda { save(current["kind"], False); }}
                        >
                            {busy == "save" and <Spinner aria-hidden="true"/>}{"Unpublish"
                                if current["published"]
                                else "Save draft"}
                        </Button>
                    </div>
                </section>}
        </div>;
}
