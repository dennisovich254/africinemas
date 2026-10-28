"""Settings → Payments (P15.3, ADR-0082): connecting the cinema's own M-Pesa.

Customers' M-Pesa payments go straight to the cinema's own Paybill or Till. The page
shows the account in use and any change waiting; the owner connects one (with a guide
to getting Daraja keys from Safaricom), sends a KES 1 test payment from their phone,
and can cancel a change before it's used. Keys are typed once and never shown again:
only the consumer key's last four characters. Other settings staff see the status.
"""

import from react { useState, useEffect }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.payments.mpesa_api {
    mpesa_settings,  # jac:ignore[W2037] authenticated endpoint
    connect_mpesa,  # jac:ignore[W2037] authenticated endpoint
    test_mpesa,  # jac:ignore[W2037] authenticated endpoint
    mpesa_test_status,  # jac:ignore[W2037] authenticated endpoint
    cancel_mpesa_change  # jac:ignore[W2037] authenticated endpoint
}
import from ..auth.session { signed_in_email }
import from ..support.SupportThread { when }
import from .form_parts { TextField, submit_with }
import from .nav { section_path }
import from ..shell.AppLink { AppLink }

glob GUIDE: list[dict[str, str]] = [
         {
             "title": "Sign in to Safaricom's developer portal",
             "text": "Go to developer.safaricom.co.ke and sign in, or make an account, with the email of the person who manages the cinema's M-Pesa."
         },
         {
             "title": "Ask to go live",
             "text": "Choose Go Live and follow the steps for your Paybill or Till. Safaricom checks it's yours with a code sent to the business administrator's phone (the one on the M-Pesa account's papers)."
         },
         {
             "title": "Choose M-Pesa Express",
             "text": "When asked which products you need, choose M-Pesa Express (Lipa na M-Pesa Online). That's the prompt customers get on their phone."
         },
         {
             "title": "Copy the keys",
             "text": "Safaricom makes a live app for you: open it to copy its Consumer Key and Consumer Secret. The Passkey comes by email to the business administrator once going live is approved."
         },
         {
             "title": "Paste them here and test",
             "text": "Fill in the form below, then send a KES 1 test payment from your phone. Your phone's prompt shows the name your Paybill or Till is registered to: it should be your business's."
         }
     ];

def:pub kind_label(kind: str) -> str {
    return "Till" if kind == "till" else "Paybill";
}

def:pub account_line(account: dict[str, any]) -> str {  # jac:ignore[W1037]
    # "Paybill 600100, Kim's Cinema Ltd" or "Till 800300 (store 700200), …".
    number = account["pays_to"];
    store = f" (store {account['shortcode']})" if account["kind"] == "till" else "";
    return f"{kind_label(account['kind'])} {number}{store}, {account[
        'registered_name'
    ]}";
}

def SecretField(
    field_id: str,
    label: str,
    value: str,
    on_value: any,  # jac:ignore[W1037]
    complete: str = "off"
) -> JsxElement {
    return
        <div className="flex min-w-0 flex-col gap-1.5">
            <Label htmlFor={field_id}>{label}</Label>
            <Input
                id={field_id}
                type="password"
                value={value}
                autoComplete={complete}
                spellCheck={False}
                className="min-h-11"
                onChange={lambda (e: any) { on_value(e.target.value); }}  # jac:ignore[W1037]
            />
        </div>;
}

def Guide -> JsxElement {
    return
        <details data-testid="mpesa-guide" className="rounded-lg border bg-card p-4">
            <summary className="min-h-11 cursor-pointer content-center font-medium">
                How to get your Daraja keys from Safaricom
            </summary>
            <ol className="mt-3 flex list-decimal flex-col gap-3 pl-5 text-sm">
                {[
                    <li key={step["title"]}>
                        <p className="font-medium">{step["title"]}</p>
                        <p className="text-muted-foreground">{step["text"]}</p>
                    </li> for step in GUIDE
                ]}
            </ol>
        </details>;
}

def:pub PaymentsSection(slug: str) -> JsxElement {
    [view, set_view] = useState(None);
    [failed, set_failed] = useState(False);
    [kind, set_kind] = useState("paybill");
    [shortcode, set_shortcode] = useState("");
    [till, set_till] = useState("");
    [name, set_name] = useState("");
    [consumer_key, set_consumer_key] = useState("");
    [consumer_secret, set_consumer_secret] = useState("");
    [passkey, set_passkey] = useState("");
    [password, set_password] = useState("");
    [phone, set_phone] = useState("");
    [busy, set_busy] = useState(False);
    [problem, set_problem] = useState("");
    [show_form, set_show_form] = useState(False);

    def taken(got: any) -> bool {  # jac:ignore[W1037]
        # Shows an answer: the new settings, or what went wrong.
        if got is None {
            set_problem("We couldn't reach AfriCinemas. Try again.");
            return False;
        }
        if not got["ok"] {
            set_problem(got["error"]["message"]);
            return False;
        }
        set_problem("");
        set_view(got);
        return True;
    }

    async def load {
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await mpesa_settings(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("mpesa_settings failed", e);
        }
        if got is None or not got["ok"] {
            set_failed(True);
            return;
        }
        set_view(got);
        if got["verified_name"] {
            set_name(got["verified_name"]);
        }
    }

    def start {
        load();
    }
    useEffect(start, []);

    async def connect {
        set_busy(True);
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await connect_mpesa(  # jac:ignore[W2037]
                slug,
                kind,
                shortcode,
                till if kind == "till" else "",
                name,
                {
                    "consumer_key": consumer_key,
                    "consumer_secret": consumer_secret,
                    "passkey": passkey
                },
                password,
                signed_in_email()
            );
        } except Exception as e {
            console.warn("connect_mpesa failed", e);
        }
        set_busy(False);
        set_password("");
        if taken(got) {
            set_consumer_key("");
            set_consumer_secret("");
            set_passkey("");
            set_show_form(False);
        }
    }

    async def send_test {
        set_busy(True);
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await test_mpesa(slug, phone);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("test_mpesa failed", e);
        }
        set_busy(False);
        taken(got);
    }

    async def check_test {
        set_busy(True);
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await mpesa_test_status(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("mpesa_test_status failed", e);
        }
        set_busy(False);
        taken(got);
    }

    async def cancel {
        set_busy(True);
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await cancel_mpesa_change(slug, signed_in_email());  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("cancel_mpesa_change failed", e);
        }
        set_busy(False);
        taken(got);
    }

    if failed {
        return
            <p role="alert" className="text-sm text-destructive">
                We couldn't load the payment settings. Refresh the page to try again.
            </p>;
    }
    shown: dict[str, any] | None = view;  # jac:ignore[W1037]
    if shown is None {
        return <Spinner aria-label="Loading the payment settings"/>;
    }
    active: dict[str, any] | None = shown["active"];  # jac:ignore[W1037]
    pending: dict[str, any] | None = shown["pending"];  # jac:ignore[W1037]
    may_change: bool = shown["may_change"];
    blocked: str = shown["blocked"];
    testing = pending is not None and pending["state"] == "testing";
    waiting = pending is not None and pending["state"] == "ready";
    form_open = may_change
        and not blocked
        and (show_form or (active is None and pending is None));
    return
        <section data-testid="payments" className="flex max-w-3xl flex-col gap-6">
            <p className="text-sm text-muted-foreground">
                Customers pay with M-Pesa straight into your own Paybill or Till: the money never passes through AfriCinemas. AfriCinemas bills its fees monthly.
            </p>
            <div
                data-testid="mpesa-active"
                className="flex flex-col gap-1 rounded-lg border bg-card p-4"
            >
                <p className="text-sm text-muted-foreground">Payments go to</p>
                {active is not None
                    and <div className="flex flex-col gap-1">
                        <p className="text-lg font-semibold">{account_line(active)}</p>
                        <p className="text-sm text-muted-foreground">
                            {f"Consumer key ending {active['key_hint']}. In use since {when(
                                active['active_from']
                            )}."}
                        </p>
                    </div>}
                {active is None
                    and <p className="text-lg font-semibold">
                        Not connected yet. Customers can't pay with M-Pesa until you connect your Paybill or Till.
                    </p>}
            </div>
            {blocked == "not_verified"
                and <p data-testid="mpesa-blocked" className="text-sm">
                    AfriCinemas verifies your business first, then you can connect M-Pesa.{" "}
                    <AppLink
                        to={section_path(slug, "verification")}
                        className="font-medium underline"
                    >
                        Go to Verification
                    </AppLink>
                </p>}
            {blocked == "not_ready"
                and <p data-testid="mpesa-blocked" className="text-sm">
                    Connecting M-Pesa isn't available right now. Try again later.
                </p>}
            {not may_change
                and <p className="text-sm text-muted-foreground">
                    Only the cinema's owner can connect or change M-Pesa.
                </p>}
            {pending is not None
                and <div
                    data-testid="mpesa-pending"
                    className="flex flex-col gap-3 rounded-lg border border-primary/40 bg-card p-4"
                >
                    <h2 className="text-lg font-semibold">
                        {"Changing to " if pending["is_change"] else "Connecting "}{account_line(
                            pending
                        )}
                    </h2>
                    {testing
                        and <p className="text-sm text-muted-foreground">
                            Send a KES 1 test payment from your phone to check the keys. Your phone's prompt names who the Paybill or Till is registered to.
                        </p>}
                    {waiting
                        and <p data-testid="mpesa-waiting" className="text-sm">
                            {f"The test payment went through. Payments go here from {when(
                                pending['active_from']
                            )}: a change waits {shown[
                                'wait_hours'
                            ]} hours, so you can cancel one you didn't make."}
                        </p>}
                    {pending["test_text"]
                        and testing
                        and <p role="status" className="text-sm">
                            {pending["test_text"]}
                        </p>}
                    {may_change
                        and testing
                        and <form
                            className="flex flex-col gap-3 sm:flex-row sm:items-end"
                            onSubmit={submit_with(send_test)}
                        >
                            <TextField
                                field_id="mpesa-test-phone"
                                label="Your M-Pesa number"
                                value={phone}
                                on_value={set_phone}
                                input_mode="tel"
                            />
                            <Button type="submit" disabled={busy} className="min-h-11">
                                Send KES 1 test
                            </Button>
                            <Button
                                type="button"
                                variant="outline"
                                disabled={busy}
                                className="min-h-11"
                                onClick={check_test}
                            >
                                I've paid it
                            </Button>
                        </form>}
                    {may_change
                        and <div>
                            <Button
                                variant="ghost"
                                disabled={busy}
                                className="min-h-11"
                                onClick={cancel}
                            >
                                {"Cancel this change"
                                    if pending["is_change"]
                                    else "Cancel"}
                            </Button>
                        </div>}
                </div>}
            {may_change
                and not blocked
                and not form_open
                and <div>
                    <Button
                        variant="outline"
                        className="min-h-11"
                        onClick={lambda { set_show_form(True); }}
                    >
                        {"Change M-Pesa" if active is not None else "Connect M-Pesa"}
                    </Button>
                </div>}
            {form_open and <Guide/>}
            {form_open
                and <form
                    data-testid="mpesa-form"
                    className="flex flex-col gap-4 rounded-lg border bg-card p-4"
                    onSubmit={submit_with(connect)}
                >
                    <h2 className="text-lg font-semibold">
                        {"Change M-Pesa" if active is not None else "Connect M-Pesa"}
                    </h2>
                    {active is not None
                        and <p className="text-sm text-muted-foreground">
                            {f"A change is tested first, then waits {shown[
                                'wait_hours'
                            ]} hours before payments go to it. Every owner gets an email."}
                        </p>}
                    <fieldset className="flex flex-col gap-2">
                        <legend className="mb-1 text-sm font-medium">
                            What customers pay into
                        </legend>
                        <div className="flex flex-wrap gap-4">
                            {[
                                <label
                                    key={option}
                                    className="flex min-h-11 items-center gap-2 text-sm"
                                >
                                    <input
                                        type="radio"
                                        name="mpesa-kind"
                                        value={option}
                                        checked={kind == option}
                                        onChange={lambda { set_kind(option); }}
                                    />
                                    {kind_label(option)}
                                </label> for option in ["paybill", "till"]
                            ]}
                        </div>
                    </fieldset>
                    <div className="grid gap-3 sm:grid-cols-2">
                        <TextField
                            field_id="mpesa-shortcode"
                            label={"Paybill number"
                                if kind == "paybill"
                                else "Store number"}
                            value={shortcode}
                            on_value={set_shortcode}
                            input_mode="numeric"
                            hint={""
                                if kind == "paybill"
                                else "The head office number Daraja shows for your Till."}
                        />
                        {kind == "till"
                            and <TextField
                                field_id="mpesa-till"
                                label="Till number"
                                value={till}
                                on_value={set_till}
                                input_mode="numeric"
                            />}
                        <TextField
                            field_id="mpesa-name"
                            label="Registered to"
                            value={name}
                            on_value={set_name}
                            hint="The business AfriCinemas verified."
                        />
                    </div>
                    <div className="grid gap-3 sm:grid-cols-2">
                        <SecretField
                            field_id="mpesa-consumer-key"
                            label="Consumer key"
                            value={consumer_key}
                            on_value={set_consumer_key}
                        />
                        <SecretField
                            field_id="mpesa-consumer-secret"
                            label="Consumer secret"
                            value={consumer_secret}
                            on_value={set_consumer_secret}
                        />
                        <SecretField
                            field_id="mpesa-passkey"
                            label="Passkey"
                            value={passkey}
                            on_value={set_passkey}
                        />
                        <SecretField
                            field_id="mpesa-password"
                            label="Your AfriCinemas password"
                            value={password}
                            on_value={set_password}
                            complete="current-password"
                        />
                    </div>
                    <p className="text-sm text-muted-foreground">
                        The keys are stored encrypted and never shown again.
                    </p>
                    <div className="flex flex-wrap gap-3">
                        <Button type="submit" disabled={busy} className="min-h-11">
                            {busy and <Spinner aria-hidden="true"/>}Save and test
                        </Button>
                        {(active is not None or pending is not None)
                            and <Button
                                type="button"
                                variant="ghost"
                                className="min-h-11"
                                onClick={lambda { set_show_form(False); }}
                            >
                                Close
                            </Button>}
                    </div>
                </form>}
            <p
                role="alert"
                data-testid="mpesa-problem"
                className="text-sm text-destructive empty:hidden"
            >
                {problem}
            </p>
        </section>;
}
