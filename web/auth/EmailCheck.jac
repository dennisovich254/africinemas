"""Confirming a staff account's email (P14.2): the banner and the page the link opens.

EmailCheckBanner, on Your cinemas and in the back office: while the email this browser
signed in with isn't confirmed, it says so, and "Send again" emails a fresh link (at
most five an hour). Nothing shows for a confirmed email, or an account without one.

VerifyEmailPage, `/verify-email#<token>` on the main site: the emailed link. It
confirms the email (confirm_email, public, so it works signed out and on another
device), takes the token out of the address, and says what's next.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { Link }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.button { Button }
import from ...components.ui.spinner { Spinner }
import from core.accounts.email_verification {
    send_email_check,  # jac:ignore[W2037] authenticated endpoint
    email_status,  # jac:ignore[W2037]
    confirm_email
}
import from .AuthLayout { AuthLayout }
import from .session { signed_in_email }

def:pub EmailCheckBanner -> JsxElement {
    [status, set_status] = useState(None);
    [note, set_note] = useState("");
    [busy, set_busy] = useState(False);
    async def load {
        try {
            answer: any = await email_status(signed_in_email());  # jac:ignore[W1037,W2037]
            if answer["ok"] {
                set_status(answer);
            }
        } except Exception as e {
            console.warn("email_status failed", e);
        }
    }
    def start {
        load();
    }
    useEffect(start, []);
    async def resend {
        set_busy(True);
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await send_email_check(signed_in_email());  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("send_email_check failed", e);
        }
        set_busy(False);
        if answer is None {
            set_note("We couldn't reach AfriCinemas. Try again.");
        } elif not answer["ok"] {
            set_note(answer["error"]["message"]);
        } elif answer["confirmed"] {
            set_status({"ok": True, "email": answer["email"] or "", "confirmed": True});
        } else {
            set_note("Sent. Check your inbox, and your spam folder.");
        }
    }
    shown: dict[str, any] = status or {};  # jac:ignore[W1037]
    if not shown or not shown["email"] or shown["confirmed"] {
        return <></>;
    }
    return
        <div
            role="status"
            data-testid="email-check"
            className="mb-4 flex flex-col gap-2 rounded-lg border bg-card p-3 text-sm sm:flex-row sm:items-center sm:justify-between"
        >
            <p>
                <span className="font-medium">Confirm your email.</span>
                {f" We sent a link to {shown[
                    'email'
                ]}. You'll need it to create a cinema and to go live."}
                {note
                    and <span
                        className="block text-muted-foreground"
                        data-testid="email-check-note"
                    >
                        {note}
                    </span>}
            </p>
            <Button
                variant="outline"
                className="min-h-11 shrink-0 px-4"
                disabled={busy}
                onClick={resend}
                data-testid="email-check-send"
            >
                {busy and <Spinner aria-hidden="true"/>}Send again
            </Button>
        </div>;
}

def:pub VerifyEmailPage -> JsxElement {
    win: any = window;  # jac:ignore[W1037,W2001]
    [state, set_state] = useState("checking");
    [message, set_message] = useState("");
    async def check {
        token: str = win.location.hash[1:];
        if not token {
            set_state("failed");
            set_message(
                "This page needs the link from your email. Open the link we sent you."
            );
            return;
        }
        # The link is spent once used: out of the address bar and history.
        win.history.replaceState(None, "", "/verify-email");
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await confirm_email(token);
        } except Exception as e {
            console.warn("confirm_email failed", e);
        }
        if answer is None {
            set_state("failed");
            set_message(
                "We couldn't reach AfriCinemas. Check your connection and open the link again."
            );
        } elif not answer["ok"] {
            set_state("failed");
            set_message(answer["error"]["message"]);
        } else {
            set_state("done");
            set_message(answer["email"]);
        }
    }
    def start {
        check();
    }
    useEffect(start, []);
    return
        <AuthLayout title="Confirm your email" description="">
            {state == "checking"
                and <p
                    role="status"
                    className="flex items-center gap-2 text-muted-foreground"
                >
                    <Spinner aria-hidden="true"/>
                    Confirming…
                </p>}{state == "done"
                and <div className="flex flex-col gap-3" data-testid="email-confirmed">
                    <p>{f"{message} is confirmed. Thank you."}</p>
                    <Button asChild={True} className="h-11 w-full">
                        <Link to="/app">Go to your cinemas</Link>
                    </Button>
                </div>}{state == "failed"
                and <Alert variant="destructive" data-testid="email-check-failed">
                    <AlertDescription>{message}</AlertDescription>
                </Alert>}
        </AuthLayout>;
}
