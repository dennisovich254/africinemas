"""Your name and your password (P12.15, ADR-0077): the back office's Your profile and a
customer's account page both use these.

NameForm saves the name others see (save_my_name). PasswordForm asks for the current
password, then the new one twice; the server applies Jac's password rules
(change_my_password). Each form says what happened in its own status line.
"""

import from react { useState }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from .PasswordField { PasswordField }
import from core.accounts.profile {
    save_my_name,  # jac:ignore[W2037] authenticated endpoint
    change_my_password  # jac:ignore[W2037] authenticated endpoint
}

glob OFFLINE: str = "We couldn't reach the server. Check your connection and try again.",
     PASSWORD_MIN: int = 8;

def:pub NameForm(name: str, on_saved: any = None) -> JsxElement {  # jac:ignore[W1037]
    [text, set_text] = useState(name);
    [busy, set_busy] = useState(False);
    [note, set_note] = useState("");

    async def save(e: any) {  # jac:ignore[W1037]
        e.preventDefault();
        set_busy(True);
        set_note("");
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await save_my_name(text);  # jac:ignore[W2037]
        } except Exception as err {
            console.warn("save_my_name failed", err);
        }
        set_busy(False);
        if got is None {
            set_note(OFFLINE);
            return;
        }
        if not got["ok"] {
            set_note(got["error"]["message"]);
            return;
        }
        set_text(got["name"]);
        set_note("Your name is saved.");
        if on_saved {
            on_saved(got["name"]);
        }
    }

    return
        <form data-testid="name-form" className="flex flex-col gap-3" onSubmit={save}>
            <div className="flex flex-col gap-1.5">
                <Label htmlFor="profile-name">Your name</Label>
                <Input
                    id="profile-name"
                    value={text}
                    maxLength={80}
                    autoComplete="name"
                    className="min-h-11"
                    onChange={lambda (e: any) { set_text(e.target.value); }}  # jac:ignore[W1037]
                />
            </div>
            <div>
                <Button type="submit" disabled={busy} className="min-h-11">
                    {"Saving…" if busy else "Save name"}
                </Button>
            </div>
            <p role="status" aria-live="polite" className="text-sm empty:hidden">
                {note}
            </p>
        </form>;
}

def:pub PasswordForm(sign_in: str) -> JsxElement {
    [current, set_current] = useState("");
    [fresh, set_fresh] = useState("");
    [again, set_again] = useState("");
    [busy, set_busy] = useState(False);
    [note, set_note] = useState("");
    [failed, set_failed] = useState(False);

    def tell(text: str, bad: bool) {
        set_note(text);
        set_failed(bad);
    }

    async def change(e: any) {  # jac:ignore[W1037]
        e.preventDefault();
        if fresh != again {
            tell("The new passwords don't match.", True);
            return;
        }
        set_busy(True);
        tell("", False);
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await change_my_password(sign_in, current, fresh);  # jac:ignore[W2037]
        } except Exception as err {
            console.warn("change_my_password failed", err);
        }
        set_busy(False);
        if got is None {
            tell(OFFLINE, True);
            return;
        }
        if not got["ok"] {
            tell(got["error"]["message"], True);
            return;
        }
        set_current("");
        set_fresh("");
        set_again("");
        tell("Your password is changed. Use the new one next time you sign in.", False);
    }

    return
        <form
            data-testid="password-form"
            className="flex flex-col gap-3"
            onSubmit={change}
        >
            <PasswordField
                id="current-password"
                label="Current password"
                value={current}
                on_change={set_current}
                auto_complete="current-password"
            />
            <PasswordField
                id="new-password"
                label="New password"
                value={fresh}
                on_change={set_fresh}
                auto_complete="new-password"
                hint={f"At least {PASSWORD_MIN} characters."}
                min_length={PASSWORD_MIN}
            />
            <PasswordField
                id="new-password-again"
                label="New password again"
                value={again}
                on_change={set_again}
                auto_complete="new-password"
                min_length={PASSWORD_MIN}
            />
            <div>
                <Button type="submit" disabled={busy} className="min-h-11">
                    {"Changing…" if busy else "Change password"}
                </Button>
            </div>
            <p
                role={"alert" if failed else "status"}
                data-testid="password-note"
                className={"text-sm empty:hidden"
                    + (" text-destructive" if failed else "")}
            >
                {note}
            </p>
        </form>;
}
