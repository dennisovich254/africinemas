"""`/legal/:document`: AfriCinemas' own legal documents (P15.0b, ADR-0078).

The terms of use, the privacy policy and the cookie and storage notice, on the main
site, linked from its footer, the sign-up page and every storefront's footer. The
cinema agreement is confidential and isn't one of these pages. Each page shows its version, the date it applies from and that it's
being reviewed, the text (legal_text.jac: drawn as React text, never as HTML), and
links to the other documents. An unknown document isn't found.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { useParams }
import from ...components.ui.spinner { Spinner }
import from core.legal.legal_api { legal_document }
import from ..theme.ThemeProvider { ThemeProvider }
import from ..storefront.venue_choice { use_title }
import from .legal_text { legal_blocks, spans }

glob DOCUMENTS: list[tuple[str, str]] = [
         ("terms", "Terms of use"),
         ("privacy", "Privacy policy"),
         ("cookies", "Cookies and storage")
     ],
     LINK: str = "font-medium text-primary underline underline-offset-4";

def:pub Inline(text: str) -> JsxElement {
    # A line's bold, code and links, as React elements.
    return
        <span>
            {[
                (
                    <strong key={f"{n}"} className="font-semibold">{s["text"]}</strong>
                        if s["kind"] == "bold"
                        else (
                            <code
                                key={f"{n}"}
                                className="rounded bg-muted px-1 text-sm"
                            >
                                {s["text"]}
                            </code>
                                if s["kind"] == "code"
                                else (
                                    <a key={f"{n}"} href={s["href"]} className={LINK}>
                                        {s["text"]}
                                    </a>
                                        if s["kind"] == "link"
                                        else <span key={f"{n}"}>{s["text"]}</span>
                                )
                        )
                ) for (n, s) in enumerate(spans(text))
            ]}
        </span>;
}

def Table(rows: list[list[str]]) -> JsxElement {
    # The first row is the header. Wide tables scroll inside their box, never the page.
    head: list[str] = rows[0] if len(rows) > 0 else [];
    body: list[list[str]] = rows[1:];
    return
        <div className="max-w-full overflow-x-auto rounded-lg border">
            <table className="w-full min-w-[32rem] border-collapse text-left text-sm">
                <thead className="bg-muted">
                    <tr>
                        {[
                            <th
                                key={f"{n}"}
                                scope="col"
                                className="px-3 py-2 font-semibold"
                            >
                                <Inline text={c}/>
                            </th> for (n, c) in enumerate(head)
                        ]}
                    </tr>
                </thead>
                <tbody>
                    {[
                        <tr key={f"{r}"} className="border-t align-top">
                            {[
                                <td key={f"{n}"} className="px-3 py-2">
                                    <Inline text={c}/>
                                </td> for (n, c) in enumerate(row)
                            ]}
                        </tr> for (r, row) in enumerate(body)
                    ]}
                </tbody>
            </table>
        </div>;
}

def:pub LegalText(text: str) -> JsxElement {
    blocks: list[dict[str, any]] = legal_blocks(text);  # jac:ignore[W1037]
    return
        <div data-testid="legal-text" className="flex flex-col gap-4 leading-relaxed">
            {[
                (
                    <h1 key={f"{n}"} className="font-display text-4xl leading-tight">
                        {b["text"]}
                    </h1>
                        if b["kind"] == "h1"
                        else (
                            <h2 key={f"{n}"} className="pt-4 text-2xl font-semibold">
                                <Inline text={b["text"]}/>
                            </h2>
                                if b["kind"] == "h2"
                                else (
                                    <h3
                                        key={f"{n}"}
                                        className="pt-2 text-lg font-semibold"
                                    >
                                        <Inline text={b["text"]}/>
                                    </h3>
                                        if b["kind"] == "h3"
                                        else (
                                            <ul
                                                key={f"{n}"}
                                                className="flex list-disc flex-col gap-1 pl-5"
                                            >
                                                {[
                                                    <li key={f"{i}"}>
                                                        <Inline text={item}/>
                                                    </li>
                                                    for (i, item) in enumerate(
                                                        b["items"]
                                                    )
                                                ]}
                                            </ul>
                                                if b["kind"] == "ul"
                                                else (
                                                    <ol
                                                        key={f"{n}"}
                                                        className="flex list-decimal flex-col gap-1 pl-5"
                                                    >
                                                        {[
                                                            <li key={f"{i}"}>
                                                                <Inline text={item}/>
                                                            </li>
                                                            for (i, item) in enumerate(
                                                                b["items"]
                                                            )
                                                        ]}
                                                    </ol>
                                                        if b["kind"] == "ol"
                                                        else (
                                                            <Table
                                                                key={f"{n}"}
                                                                rows={b["rows"]}
                                                            />
                                                                if b["kind"] == "table"
                                                                else (
                                                                    <hr
                                                                        key={f"{n}"}
                                                                        className="my-2"
                                                                    />
                                                                        if b["kind"]
                                                                            == "hr"
                                                                        else <p
                                                                            key={f"{n}"}
                                                                        >
                                                                            <Inline
                                                                                text={b[
                                                                                    "text"
                                                                                ]}
                                                                            />
                                                                        </p>
                                                                )
                                                        )
                                                )
                                        )
                                )
                        )
                ) for (n, b) in enumerate(blocks)
            ]}
        </div>;
}

def:pub LegalLinks(current: str = "") -> JsxElement {
    # The four documents, for the page's own navigation.
    return
        <nav aria-label="Legal documents">
            <ul className="flex flex-wrap gap-x-6 gap-y-1 text-sm">
                {[
                    <li key={key}>
                        <a
                            href={f"/legal/{key}"}
                            aria-current={"page" if key == current else None}
                            className={"inline-flex min-h-11 items-center underline-offset-4 hover:underline"
                                + (" font-semibold" if key == current else "")}
                        >
                            {label}
                        </a>
                    </li> for (key, label) in DOCUMENTS
                ]}
            </ul>
        </nav>;
}

def:pub LegalPage -> JsxElement {
    params: any = useParams();  # jac:ignore[W1037,W1051]
    name: str = params["document"] or "";
    [found, set_found] = useState(None);
    [failed, set_failed] = useState(False);

    async def load {
        set_found(None);
        set_failed(False);
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await legal_document(name);
        } except Exception as e {
            console.warn("legal_document failed", e);
        }
        if got is None or not got["ok"] {
            set_failed(True);
            return;
        }
        set_found(got);
    }

    def start {
        load();
    }
    useEffect(start, [name]);

    shown: dict[str, any] | None = found;  # jac:ignore[W1037]
    use_title(shown["title"] if shown is not None else "AfriCinemas");
    content: any = None;  # jac:ignore[W1037]
    if failed {
        content = <p role="alert" data-testid="legal-missing">
            We couldn't find that page. Choose one of the documents above.
        </p>;
    } elif shown is None {
        content = <Spinner aria-label="Loading"/>;
    } else {
        content = <article className="flex flex-col gap-4">
            <p
                data-testid="legal-version"
                className="rounded-lg border bg-muted px-4 py-3 text-sm"
            >
                {f"{shown['note']} Applies from {shown['applies_from']}."}
            </p>
            <LegalText text={shown["text"]}/>
        </article>;
    }
    return
        <ThemeProvider surface="storefront">
            <div
                className="mx-auto flex min-h-svh w-full max-w-3xl flex-col gap-6 px-4 py-8"
            >
                <header className="flex flex-col gap-2 border-b pb-4">
                    <a
                        href="/"
                        className="inline-flex min-h-11 items-center font-semibold"
                    >
                        AfriCinemas
                    </a>
                    <LegalLinks current={name}/>
                </header>
                <main data-testid="legal-page" className="min-w-0">{content}</main>
            </div>
        </ThemeProvider>;
}
