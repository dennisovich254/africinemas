"""Settings -> Documents (P14.3d, ADR-0069): the PDFs a cinema shows visitors.

Its KFCB film exhibition licence, county business permit, food and health certificate,
or any other, each a PDF with a title, linked from every storefront footer. Up to ten.
The server checks each PDF and rebuilds it from its pages (core/catalog/documents.jac);
a refused file says why. Removing asks first.
"""

import from react { useState, useEffect }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.catalog.documents {
    public_documents_admin,  # jac:ignore[W2037] authenticated endpoint
    upload_public_document,  # jac:ignore[W2037]
    remove_public_document  # jac:ignore[W2037]
}
import from .form_parts { read_as_base64, submit_with }
import from .PdfDrop { PdfDrop }

def:pub DocumentsSection(slug: str) -> JsxElement {
    [listed, set_listed] = useState(None);
    [suggested, set_suggested] = useState([]);
    [title, set_title] = useState("");
    [file, set_file] = useState(None);
    [busy, set_busy] = useState(False);
    [asking, set_asking] = useState("");
    [message, set_message] = useState("");
    [failed, set_failed] = useState("");

    def seen(answer: any) {  # jac:ignore[W1037]
        set_listed(answer["documents"]);
        set_suggested(answer["suggested"]);
    }

    async def load {
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await public_documents_admin(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("documents failed", e);
        }
        if answer is None {
            set_failed("We couldn't load this. Refresh the page to try again.");
        } elif not answer["ok"] {
            set_failed(answer["error"]["message"]);
        } else {
            set_failed("");
            seen(answer);
        }
    }
    def start {
        load();
    }
    useEffect(start, [slug]);

    def chose(picked: any) {  # jac:ignore[W1037]
        # The PDF to upload; its name, without ".pdf", as the title until one is typed.
        set_file(picked);
        set_failed("");
        set_message("");
        if not title.strip() {
            name: str = picked.name or "";
            stem = name[:-4] if name.lower().endswith(".pdf") else name;
            set_title(" ".join(" ".join(stem.split("_")).split("-")).strip());
        }
    }

    async def upload {
        set_message("");
        if not title.strip() {
            set_failed("Give the document a title.");
            return;
        }
        if file is None {
            set_failed("Choose the PDF to upload.");
            return;
        }
        set_busy(True);
        answer: any = None;  # jac:ignore[W1037]
        try {
            encoded = await read_as_base64(file);
            answer = await upload_public_document(slug, title, encoded);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("upload failed", e);
        }
        set_busy(False);
        if answer is None {
            set_failed("We couldn't upload it. Check your connection and try again.");
            return;
        }
        if not answer["ok"] {
            set_failed(answer["error"]["message"]);
            return;
        }
        set_failed("");
        seen(answer);
        set_title("");
        set_file(None);
        set_message("Uploaded. It's linked from your storefront's footer now.");
    }

    async def remove(doc_id: str) {
        set_busy(True);
        set_message("");
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await remove_public_document(slug, doc_id);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("remove failed", e);
        }
        set_busy(False);
        set_asking("");
        if answer is None or not answer["ok"] {
            set_failed(
                answer["error"]["message"]
                    if answer is not None
                    else "We couldn't reach AfriCinemas. Try again."
            );
            return;
        }
        set_failed("");
        seen(answer);
        set_message("Removed from your storefront.");
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
    rows: list[dict[str, str]] = listed;
    ideas: list[str] = suggested;
    return
        <div data-testid="documents" className="flex max-w-2xl flex-col gap-6">
            <p className="text-sm text-muted-foreground">
                Licences and certificates you'd like visitors to see, such as your KFCB film exhibition licence. Each is linked from the footer of every page of your storefront.
            </p>
            {len(rows) > 0
                and <ul className="flex flex-col divide-y rounded-lg border bg-card">
                    {[
                        <li
                            key={d["id"]}
                            data-testid="document-row"
                            className="flex flex-wrap items-center justify-between gap-2 px-4 py-3"
                        >
                            <span className="font-medium">{d["title"]}</span>
                            {(
                                <span className="flex flex-wrap items-center gap-2">
                                    <span className="text-sm">Remove it?</span>
                                    <Button
                                        type="button"
                                        variant="destructive"
                                        className="min-h-11 px-4"
                                        disabled={busy}
                                        data-testid="confirm-remove-document"
                                        onClick={lambda { remove(d["id"]); }}
                                    >
                                        Remove
                                    </Button>
                                    <Button
                                        type="button"
                                        variant="outline"
                                        className="min-h-11 px-4"
                                        onClick={lambda { set_asking(""); }}
                                    >
                                        Keep
                                    </Button>
                                </span>
                            )
                                if asking == d["id"]
                                else <Button
                                    type="button"
                                    variant="outline"
                                    className="min-h-11 px-4"
                                    data-testid="remove-document"
                                    aria-label={f"Remove {d['title']}"}
                                    onClick={lambda { set_asking(d["id"]); }}
                                >
                                    Remove
                                </Button>}
                        </li> for d in rows
                    ]}
                </ul>}
            <form
                className="flex flex-col gap-4 rounded-lg border bg-card p-4"
                onSubmit={submit_with(lambda { upload(); })}
                data-testid="document-upload"
            >
                <h3 className="font-semibold">Add a document</h3>
                <PdfDrop
                    field_id="document-file"
                    label="PDF"
                    chosen={file.name if file is not None else ""}
                    busy={busy}
                    disabled={busy}
                    on_file={chose}
                />
                <div className="flex flex-col gap-1.5">
                    <Label htmlFor="document-title">Title</Label>
                    <Input
                        id="document-title"
                        value={title}
                        list="document-titles"
                        maxLength={80}
                        className="min-h-11"
                        onChange={lambda (e: any) { set_title(e.target.value); }}  # jac:ignore[W1037]
                    />
                    <datalist id="document-titles">
                        {[<option key={t} value={t}/> for t in ideas]}
                    </datalist>
                </div>
                {failed
                    and <Alert variant="destructive" role="alert">
                        <AlertDescription>{failed}</AlertDescription>
                    </Alert>}
                <p
                    role="status"
                    aria-live="polite"
                    className="text-sm empty:hidden"
                    data-testid="documents-saved"
                >
                    {message}
                </p>
                <Button type="submit" className="min-h-11 w-fit px-5" disabled={busy}>
                    {busy and <Spinner aria-hidden="true"/>}Upload
                </Button>
            </form>
        </div>;
}
