"""My account → Your data (P15.0): download it, or delete the account.

Download my data saves a JSON file of everything the cinema holds about the customer
(core/accounts/customer_data.jac, my_data). Delete my account asks for the password,
says what's kept and why, and that it happens in seven days (owner, 2026-10-29); until
then the account is locked, and Keep my account cancels it. The page shows only this
while a deletion is waiting.
"""

import from react { useState }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from core.accounts.customer_data {
    my_data,  # jac:ignore[W2037] authenticated endpoint
    request_account_deletion,  # jac:ignore[W2037] authenticated endpoint
    cancel_account_deletion  # jac:ignore[W2037] authenticated endpoint
}
import from ..backoffice.form_parts { on_input }
import from .showtimes { long_day_label }

def _save_json(name: str, data: any) {  # jac:ignore[W1037]
    # Hands the customer the file.
    win: any = window;  # jac:ignore[W1037,W2001]
    text: str = JSON.stringify(data, None, 2);  # jac:ignore[W2001,W6001,W6002]
    blob: any = new(win.Blob, [text], {"type": "application/json"});  # jac:ignore[W1037]
    url: str = win.URL.createObjectURL(blob);
    link: any = win.document.createElement("a");  # jac:ignore[W1037,W6001]
    link.href = url;
    link.download = name;
    link.click();
    win.URL.revokeObjectURL(url);
}

def:pub YourData(
    slug: str,
    deleting: any,  # jac:ignore[W1037] {"asked_at", "due"}, or None
    tz: str,
    on_changed: any  # jac:ignore[W1037]
) -> JsxElement {
    [busy, set_busy] = useState("");
    [problem, set_problem] = useState("");
    [asking, set_asking] = useState(False);
    [password, set_password] = useState("");
    [kept, set_kept] = useState([]);

    async def download {
        set_busy("download");
        set_problem("");
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await my_data(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("my_data failed", e);
        }
        set_busy("");
        if got is None or not got["ok"] {
            set_problem("We couldn't get your data. Try again.");
            return;
        }
        _save_json(f"my-data-{slug}.json", got["data"]);
    }

    async def delete_it(e: any) {  # jac:ignore[W1037]
        e.preventDefault();
        set_busy("delete");
        set_problem("");
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await request_account_deletion(slug, password);  # jac:ignore[W2037]
        } except Exception as err {
            console.warn("request_account_deletion failed", err);
        }
        set_busy("");
        if got is None or not got["ok"] {
            set_problem(
                got["error"]["message"]
                    if got is not None
                    else "We couldn't reach the cinema. Try again."
            );
            return;
        }
        set_password("");
        set_asking(False);
        set_kept(got["kept"]);
        on_changed();
    }

    async def keep {
        set_busy("keep");
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await cancel_account_deletion(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("cancel_account_deletion failed", e);
        }
        set_busy("");
        if got is None or not got["ok"] {
            set_problem("We couldn't reach the cinema. Try again.");
            return;
        }
        on_changed();
    }

    pending: dict[str, str] | None = deleting;  # jac:ignore[W1037]
    told: list[str] = kept;
    return
        <section className="flex flex-col gap-3" data-testid="your-data">
            <h2 className="text-lg font-semibold">Your data</h2>
            {pending is not None
                and <div
                    role="status"
                    className="flex flex-col gap-2 rounded-lg border border-destructive/40 bg-destructive/5 p-4"
                    data-testid="account-deleting"
                >
                    <p className="font-medium">
                        {f"Your account will be deleted on {long_day_label(
                            pending['due'], tz
                        )}."}
                    </p>
                    <p className="text-sm">
                        Until then it's locked. Keep it if you change your mind.
                    </p>
                    {len(told) > 0
                        and <ul
                            className="list-disc pl-5 text-sm"
                            data-testid="account-kept"
                        >
                            {[<li key={f"{i}"}>{k}</li> for (i, k) in enumerate(told)]}
                        </ul>}
                    <div>
                        <Button
                            className="min-h-11"
                            disabled={busy != ""}
                            onClick={keep}
                            data-testid="keep-account"
                        >
                            Keep my account
                        </Button>
                    </div>
                </div>}
            <p className="text-sm text-muted-foreground">
                A copy of everything this cinema holds about you: your account, your bookings and what you paid, and your choices about offers and apps.
            </p>
            <div>
                <Button
                    variant="outline"
                    className="min-h-11"
                    disabled={busy != ""}
                    onClick={download}
                    data-testid="download-data"
                >
                    {"Getting your data…" if busy == "download" else "Download my data"}
                </Button>
            </div>
            {pending is None
                and not asking
                and <div>
                    <Button
                        variant="outline"
                        className="min-h-11 text-destructive"
                        onClick={lambda {
                            set_problem("");
                            set_asking(True);
                        }}
                        data-testid="delete-account"
                    >
                        Delete my account
                    </Button>
                </div>}
            {pending is None
                and asking
                and <form
                    className="flex flex-col gap-3 rounded-lg border p-4"
                    onSubmit={delete_it}
                    data-testid="delete-account-form"
                >
                    <p className="text-sm">
                        Your account is deleted seven days after you ask: your sign-in, your saved bookings and your choices. Until then it's locked, and you can keep it. Your orders stay, as the cinema's sales records, without your email once the showtime has passed; tickets still to come keep working.
                    </p>
                    <div className="flex flex-col gap-1.5">
                        <Label htmlFor="delete-password">Your password</Label>
                        <Input
                            id="delete-password"
                            type="password"
                            autoComplete="current-password"
                            value={password}
                            onChange={on_input(set_password)}
                            className="min-h-11"
                        />
                    </div>
                    <div className="flex flex-wrap gap-2">
                        <Button
                            type="submit"
                            variant="destructive"
                            className="min-h-11"
                            disabled={busy != ""}
                        >
                            {"Asking…" if busy == "delete" else "Delete my account"}
                        </Button>
                        <Button
                            type="button"
                            variant="ghost"
                            className="min-h-11"
                            onClick={lambda { set_asking(False); }}
                        >
                            Cancel
                        </Button>
                    </div>
                </form>}
            <p role="alert" className="text-sm text-destructive empty:hidden">
                {problem}
            </p>
        </section>;
}
