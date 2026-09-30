"""Small form pieces shared by the setup pages (P3.7a).

- TextField: a visible label, the input, and its error right under it, linked with
  aria-describedby and announced (role="alert").
- ConfirmDelete: the in-page "are you sure?" step before anything is deleted.
- field_for: which field a server refusal belongs to, so it's shown next to it.
- read_as_base64: a chosen file's contents, for the upload endpoints (logos, posters).
- on_input / submit_with: event handlers that hand over just the text, or just the
  submit, so pages never handle browser events themselves.
"""

import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.textarea { Textarea }

def:pub error_id(field_id: str) -> str {
    return f"{field_id}-error";
}

def:pub FieldError(field_id: str, error: str) -> JsxElement {
    return
        <p
            id={error_id(field_id)}
            role="alert"
            className={"text-sm text-destructive" if error else "sr-only"}
        >
            {error}
        </p>;
}

def:pub TextField(  # jac:ignore[W3030] a form field: id, label, value, error, handlers and input options
    field_id: str,
    label: str,
    value: str,
    error: str = "",
    on_value: any = None,  # jac:ignore[W1037]
    on_blur: any = None,  # jac:ignore[W1037]
    multiline: bool = False,
    input_mode: str = "text",
    hint: str = "",
    auto_focus: bool = False
) -> JsxElement {
    described = error_id(field_id) if error else None;
    control: any = None;  # jac:ignore[W1037]
    if multiline {
        control = <Textarea
            id={field_id}
            value={value}
            rows={4}
            aria-invalid={"true" if error else "false"}
            aria-describedby={described}
            onChange={on_input(on_value)}
            onBlur={on_blur}
        />;
    } else {
        control = <Input
            id={field_id}
            value={value}
            inputMode={input_mode}
            autoFocus={auto_focus}
            aria-invalid={"true" if error else "false"}
            aria-describedby={described}
            onChange={on_input(on_value)}
            onBlur={on_blur}
            className="min-h-11"
        />;
    }
    return
        <div className="flex min-w-0 flex-col gap-1.5">
            <Label htmlFor={field_id}>{label}</Label>
            {control}
            {hint and <p className="text-sm text-muted-foreground">{hint}</p>}
            {error and <FieldError field_id={field_id} error={error}/>}
        </div>;
}

def:pub ConfirmDelete(
    question: str,
    detail: str,
    confirm_label: str,
    on_confirm: any,  # jac:ignore[W1037]
    on_cancel: any,  # jac:ignore[W1037]
    busy: bool = False
) -> JsxElement {
    return
        <div
            data-testid="confirm-delete"
            role="group"
            aria-label={question}
            className="flex flex-col gap-3 rounded-lg border border-destructive/40 p-4"
        >
            <p className="font-medium">{question}</p>
            {detail and <p className="text-sm text-muted-foreground">{detail}</p>}
            <div className="flex flex-wrap gap-3">
                <Button
                    variant="destructive"
                    className="min-h-11 px-5"
                    disabled={busy}
                    onClick={on_confirm}
                >
                    {confirm_label}
                </Button>
                <Button
                    variant="ghost"
                    className="min-h-11 px-5"
                    disabled={busy}
                    onClick={on_cancel}
                >
                    Cancel
                </Button>
            </div>
        </div>;
}

def:pub field_for(code: str, fields: dict[str, str]) -> str {
    # The field a refusal code belongs to ("invalid_title" -> fields["title"]), or "".
    for key in fields {
        if code == f"invalid_{key}" {
            return fields[key];
        }
    }
    if code == "name_taken" and "name" in fields {
        return fields["name"];
    }
    return "";
}

def:pub on_input(use_text: any) -> any {  # jac:ignore[W1037]
    # An onChange handler that passes the field's text to `use_text`.
    def handler(e: any) {  # jac:ignore[W1037]
        if use_text {
            use_text(e.target.value);
        }
    }
    return handler;
}

def:pub submit_with(action: any) -> any {  # jac:ignore[W1037]
    # An onSubmit handler that stops the page reloading and runs `action`.
    def handler(e: any) {  # jac:ignore[W1037]
        e.preventDefault();
        action();
    }
    return handler;
}

def:pub read_as_base64(file: any) -> any {  # jac:ignore[W1037]
    # A promise of a chosen file's contents as base64 (no "data:" prefix), for uploads.
    def run(resolve: any, reject: any) {  # jac:ignore[W1037]
        win: any = window;  # jac:ignore[W1037,W2001]
        reader_class: any = win.FileReader;  # jac:ignore[W1037]
        reader: any = new(reader_class);  # jac:ignore[W1037]
        def done {
            text: str = reader.result;
            resolve(text.split(",")[1]);
        }
        reader.onload = done;
        reader.onerror = reject;
        reader.readAsDataURL(file);
    }
    return new(Promise, run);  # jac:ignore[W2001]
}
