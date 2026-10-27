"""`/app/:slug/agreement`: the cinema agreement (P15.1, ADR-0079), and the notice above
every back-office page until the current version is accepted.

AgreementSection shows the agreement's version, what was accepted (the version, by whom,
when) and the text. The owner ticks that they've read it and accepts it for the cinema;
the version they accept is the one on the page, so a change since they opened it is
refused. AgreementNotice asks the owner to accept it and tells other staff when sales
are paused for a new version. Nobody but the cinema's own team sees the text: the
agreement is confidential.
"""

import from react { useState, useEffect }
import from ...components.ui.button { Button }
import from ...components.ui.spinner { Spinner }
import from core.legal.agreement_api {
    cinema_agreement_status,  # jac:ignore[W2037] authenticated endpoint
    cinema_agreement_text,  # jac:ignore[W2037]
    accept_cinema_agreement  # jac:ignore[W2037]
}
import from ..auth.session { signed_in_email }
import from ..legal.LegalPage { LegalText }
import from .nav { section_path }
import from ..shell.AppLink { AppLink }

def _day(iso: str) -> str {
    return iso.split("T")[0] if iso else "";
}

def:pub AgreementNotice(slug: str, section: str) -> JsxElement {
    [status, set_status] = useState(None);

    async def load {
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await cinema_agreement_status(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("cinema_agreement_status failed", e);
        }
        if got is not None and got["ok"] {
            set_status(got);
        }
    }

    def start {
        load();
    }
    useEffect(start, [slug, section]);

    shown: dict[str, any] | None = status;  # jac:ignore[W1037]
    if shown is None or not shown["needs_acceptance"] or section == "agreement" {
        return <span className="hidden"/>;
    }
    if shown["may_accept"] {
        return
            <div
                role="region"
                aria-label="Cinema agreement"
                data-testid="agreement-notice"
                className="flex flex-wrap items-center gap-3 rounded-xl bg-card px-4 py-3 ring-1 ring-foreground/10"
            >
                <p className="min-w-0 flex-1 text-sm">
                    {"A new version of the cinema agreement is waiting for you. Sales are paused until you accept it."
                        if not shown["may_sell"]
                        else "Read and accept the cinema agreement. Your cinema can't go live without it."}
                </p>
                <AppLink
                    to={section_path(slug, "agreement")}
                    className="inline-flex min-h-11 items-center rounded-md bg-primary px-4 text-sm font-medium text-primary-foreground"
                >
                    Read the agreement
                </AppLink>
            </div>;
    }
    if not shown["may_sell"] {
        return
            <p
                role="alert"
                data-testid="agreement-notice"
                className="rounded-xl bg-card px-4 py-3 text-sm ring-1 ring-foreground/10"
            >
                Sales are paused until your cinema's owner accepts the new cinema agreement.
            </p>;
    }
    return <span className="hidden"/>;
}

def:pub AgreementSection(slug: str, cinema: str) -> JsxElement {
    [status, set_status] = useState(None);
    [doc, set_doc] = useState(None);
    [failed, set_failed] = useState(False);
    [ticked, set_ticked] = useState(False);
    [busy, set_busy] = useState(False);
    [note, set_note] = useState("");

    async def load {
        seen: any = None;  # jac:ignore[W1037]
        text: any = None;  # jac:ignore[W1037]
        try {
            seen = await cinema_agreement_status(slug);  # jac:ignore[W2037]
            text = await cinema_agreement_text(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("agreement load failed", e);
        }
        if seen is None or text is None or not seen["ok"] or not text["ok"] {
            set_failed(True);
            return;
        }
        set_status(seen);
        set_doc(text);
    }

    def start {
        load();
    }
    useEffect(start, [slug]);

    async def accept {
        shown_doc: dict[str, any] = doc;  # jac:ignore[W1037]
        set_busy(True);
        set_note("");
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await accept_cinema_agreement(  # jac:ignore[W2037]
                slug, shown_doc["version"], signed_in_email()
            );
        } except Exception as e {
            console.warn("accept_cinema_agreement failed", e);
        }
        set_busy(False);
        if got is None or not got["ok"] {
            set_note(
                got["error"]["message"]
                    if got is not None
                    else "We couldn't save that. Try again."
            );
            load();
            return;
        }
        set_note(
            f"Accepted. Thank you: {cinema} has accepted version {got['version']}."
        );
        load();
    }

    if failed {
        return
            <p role="alert" className="text-sm text-destructive">
                We couldn't load the agreement. Refresh the page to try again.
            </p>;
    }
    shown: dict[str, any] | None = status;  # jac:ignore[W1037]
    text_shown: dict[str, any] | None = doc;  # jac:ignore[W1037]
    if shown is None or text_shown is None {
        return <Spinner aria-label="Loading the agreement"/>;
    }
    accepted: dict[str, any] | None = shown["accepted"];  # jac:ignore[W1037]
    return
        <section data-testid="agreement" className="flex max-w-3xl flex-col gap-6">
            <div className="flex flex-col gap-2 rounded-lg border bg-card p-4">
                <p className="text-sm" data-testid="agreement-version">
                    {f"Version {text_shown['version']}. {text_shown['note']}"}
                </p>
                <p className="text-sm" data-testid="agreement-accepted">
                    {f"Accepted: version {accepted['version']}, by {accepted['email']
                        or 'the owner'} on {_day(accepted['at'])}."
                        if accepted is not None
                        else "Not accepted yet."}
                </p>
                <p role="status" aria-live="polite" className="text-sm empty:hidden">
                    {note}
                </p>
            </div>
            {shown["needs_acceptance"]
                and shown["may_accept"]
                and <div
                    data-testid="agreement-accept"
                    className="flex flex-col gap-3 rounded-lg border bg-card p-4"
                >
                    <label
                        className="flex min-h-11 cursor-pointer items-center gap-3 text-sm"
                    >
                        <input
                            type="checkbox"
                            id="agreement-read"
                            className="size-5"
                            checked={ticked}
                            onChange={lambda { set_ticked(not ticked); }}
                        />
                        {f"I've read the cinema agreement and accept it on behalf of {cinema}."}
                    </label>
                    <div>
                        <Button
                            disabled={busy or not ticked}
                            className="min-h-11"
                            onClick={accept}
                        >
                            {"Accepting…" if busy else "Accept the agreement"}
                        </Button>
                    </div>
                </div>}
            {shown["needs_acceptance"]
                and not shown["may_accept"]
                and <p className="text-sm text-muted-foreground">
                    Only your cinema's owner can accept the agreement.
                </p>}
            <LegalText text={text_shown["text"]}/>
        </section>;
}
