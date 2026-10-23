"""`/sign-in` and `/join` on the platform's address: its own sign-in (P13.1b.a, P13.1b.b).

Platform staff sign in with their platform account, never a cinema's. There is no
sign-up: a super admin's invitation, or the link scripts/platform_setup.jac prints for
the settings' super admins, opens /join#<token>, where they choose their
password (or a new one); the token stays in the address's fragment, which browsers
never send to the server. Both pages leave cinema sign-ins in this browser alone, and
record the sign-in in the platform's audit log (P13.3).
"""

import from react { useState }
import from "@jac/runtime" { Navigate, useNavigate, jacIsLoggedIn }
import from ...components.ui.button { Button }
import from ...components.ui.field { FieldGroup }
import from ...components.ui.spinner { Spinner }
import from core.platform.staff_api { platform_join }
import from core.platform.audit_api { platform_signed_in }  # jac:ignore[W2037] authenticated endpoint
import from ..auth.AuthLayout { AuthLayout, EmailField, FormError }
import from ..auth.PasswordField { PasswordField }
import from .platform_session { platform_sign_in, platform_sign_in_as }

glob BRAND: str = "AfriCinemas platform",
     HOME: str = "/sign-in",
     OFFLINE: str = "We couldn't reach AfriCinemas. Check your connection and try again.";

async def record_sign_in {
    # Into the platform's audit log (P13.3); a sign-in still works if this fails.
    try {
        await platform_signed_in();  # jac:ignore[W2037]
    } except Exception as e {
        console.warn("platform_signed_in failed", e);
    }
}

def:pub PlatformSignInPage -> JsxElement {
    nav: any = useNavigate();  # jac:ignore[W1037,W1051]
    [email, set_email] = useState("");
    [password, set_password] = useState("");
    [busy, set_busy] = useState(False);
    [error, set_error] = useState("");
    if jacIsLoggedIn() {
        return <Navigate to="/" replace={True}/>;
    }
    async def submit(e: any) {  # jac:ignore[W1037]
        e.preventDefault();
        if not email.strip() or not password {
            set_error("Enter your email and password.");
            return;
        }
        set_busy(True);
        set_error("");
        outcome: str = "";
        outcome = await platform_sign_in(email, password);
        set_busy(False);
        if outcome == "ok" {
            await record_sign_in();
            nav("/");
        } elif outcome == "offline" {
            set_error(OFFLINE);
        } else {
            set_error("Email or password is incorrect.");
        }
    }
    return
        <AuthLayout title="Sign in" description="" home={HOME} brand={BRAND}>
            <form onSubmit={submit} noValidate={True} data-testid="platform-sign-in">
                <FieldGroup>
                    <FormError message={error}/>
                    <EmailField value={email} on_change={set_email}/>
                    <PasswordField
                        id="password"
                        label="Password"
                        value={password}
                        on_change={set_password}
                        auto_complete="current-password"
                    />
                    <Button type="submit" disabled={busy} className="h-11 w-full">
                        {busy and <Spinner aria-hidden="true"/>}{"Signing in…"
                            if busy
                            else "Sign in"}
                    </Button>
                </FieldGroup>
            </form>
        </AuthLayout>;
}

def:pub PlatformJoinPage -> JsxElement {
    nav: any = useNavigate();  # jac:ignore[W1037,W1051]
    win: any = window;  # jac:ignore[W1037,W2001]
    token: str = win.location.hash[1:];
    [password, set_password] = useState("");
    [again, set_again] = useState("");
    [busy, set_busy] = useState(False);
    [error, set_error] = useState("");
    async def submit(e: any) {  # jac:ignore[W1037]
        e.preventDefault();
        if len(password) < 8 {
            set_error("Use a password of at least 8 characters.");
            return;
        }
        if password != again {
            set_error("The two passwords don't match.");
            return;
        }
        set_busy(True);
        set_error("");
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await platform_join(token, password);
        } except Exception as e {
            console.warn("platform_join failed", e);
        }
        if answer is None {
            set_busy(False);
            set_error(OFFLINE);
            return;
        }
        if not answer["ok"] {
            set_busy(False);
            set_error(answer["error"]["message"]);
            return;
        }
        signed_in: bool = await platform_sign_in_as(answer["sign_in_name"], password);
        if signed_in {
            await record_sign_in();
        }
        set_busy(False);
        # Out of the address bar and history: the link is spent.
        win.history.replaceState(None, "", "/join");
        nav("/" if signed_in else HOME, {"replace": True});
    }
    return
        <AuthLayout
            title="Set your password"
            description="Choose a password for your account."
            home={HOME}
            brand={BRAND}
        >
            {not token
                and <FormError
                    message="This page needs the link from your invitation. Open the link you were sent."
                />}{token
                and <form
                    onSubmit={submit}
                    noValidate={True}
                    data-testid="platform-join"
                >
                    <FieldGroup>
                        <FormError message={error}/>
                        <PasswordField
                            id="password"
                            label="New password"
                            value={password}
                            on_change={set_password}
                            auto_complete="new-password"
                            hint="At least 8 characters."
                            min_length={8}
                        />
                        <PasswordField
                            id="password-again"
                            label="New password again"
                            value={again}
                            on_change={set_again}
                            auto_complete="new-password"
                        />
                        <Button type="submit" disabled={busy} className="h-11 w-full">
                            {busy and <Spinner aria-hidden="true"/>}{"Saving…"
                                if busy
                                else "Set password and sign in"}
                        </Button>
                    </FieldGroup>
                </form>}
        </AuthLayout>;
}
