"""A PDF chosen by dropping it on a dashed box or clicking it (P14.3d).

The same shape as the poster picker (MovieEditor's MediaPicker): the box is the file
input's label, so clicking it, or tabbing to the visually hidden input, opens the file
chooser. A dropped or chosen file that isn't a PDF is refused here with a message; the
server checks it again (core/catalog/documents.jac).
"""

import from react { useState }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Pdf01Icon }
import from ...components.ui.spinner { Spinner }

glob MAX_BYTES: int = 10 * 1024 * 1024;

def is_pdf(file: any) -> bool {  # jac:ignore[W1037]
    name: str = (file.name or "").lower();
    return file.type == "application/pdf" or name.endswith(".pdf");
}

def:pub PdfDrop(  # jac:ignore[W3030] a file field: id, label, state and handlers
    field_id: str,
    label: str,
    chosen: str,
    busy: bool,
    disabled: bool,
    on_file: any,  # jac:ignore[W1037]
    hint: str = "Up to 10 MB and 50 pages, without a password."
) -> JsxElement {
    # `chosen`: the name of the file picked (or the PDF already there), "" for none.
    [over, set_over] = useState(False);
    [problem, set_problem] = useState("");

    def take(file: any) {  # jac:ignore[W1037]
        if not is_pdf(file) {
            set_problem("Choose a PDF file.");
            return;
        }
        if file.size > MAX_BYTES {
            set_problem("Choose a PDF of up to 10 MB.");
            return;
        }
        set_problem("");
        on_file(file);
    }
    def dropped(e: any) {  # jac:ignore[W1037]
        e.preventDefault();
        set_over(False);
        if not disabled and len(e.dataTransfer.files) > 0 {
            take(e.dataTransfer.files[0]);
        }
    }
    def picked(e: any) {  # jac:ignore[W1037]
        if len(e.target.files) > 0 {
            take(e.target.files[0]);
        }
        e.target.value = "";
    }
    def dragging(e: any) {  # jac:ignore[W1037]
        e.preventDefault();
        set_over(True);
    }

    frame = "border-foreground/60 bg-muted"
        if over
        else "bg-muted/40 hover:border-foreground/40";
    return
        <div className="flex flex-col gap-1.5" data-testid={f"{field_id}-drop"}>
            <span className="text-sm font-medium">{label}</span>
            <label
                htmlFor={field_id}
                onDragOver={dragging}
                onDragLeave={lambda { set_over(False); }}
                onDrop={dropped}
                className={"relative flex min-h-36 w-full cursor-pointer flex-col items-center justify-center gap-2 rounded-lg border-2 border-dashed px-4 py-6 text-center text-sm "
                    + frame}
            >
                <HugeiconsIcon
                    icon={Pdf01Icon}
                    size={32}
                    strokeWidth={1.5}
                    aria-hidden="true"
                    className="text-muted-foreground"
                />
                {(
                    <span className="flex flex-col gap-0.5">
                        <span
                            className="font-medium break-all"
                            data-testid={f"{field_id}-chosen"}
                        >
                            {chosen}
                        </span>
                        <span className="text-muted-foreground">
                            Choose another, or drop it here
                        </span>
                    </span>
                )
                    if chosen
                    else <span className="flex flex-col gap-0.5">
                        <span className="font-medium">Choose a PDF</span>
                        <span className="text-muted-foreground">
                            or drag and drop it here
                        </span>
                    </span>}
                {busy
                    and <span
                        className="absolute inset-0 flex items-center justify-center gap-2 rounded-lg bg-background/80"
                    >
                        <Spinner aria-hidden="true"/>
                        Uploading…
                    </span>}
            </label>
            <input
                id={field_id}
                type="file"
                accept="application/pdf,.pdf"
                disabled={disabled}
                aria-label={label}
                aria-describedby={f"{field_id}-hint"}
                onChange={picked}
                className="sr-only"
            />
            <p id={f"{field_id}-hint"} className="text-sm text-muted-foreground">
                {hint}
            </p>
            {problem
                and <p role="alert" className="text-sm text-destructive">{problem}</p>}
        </div>;
}
