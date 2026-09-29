"""`/login`: staff sign in with their email and password, then pick a cinema at `/app`."""

import from react { useState }
import from "@jac/runtime" { Navigate, useNavigate, jacIsLoggedIn }
import from ...components.ui.button { Button }
import from ...components.ui.field { FieldGroup }
import from ...components.ui.spinner { Spinner }
import from .AuthLayout { AuthLayout, AuthFooter, EmailField, FormError }
import from .PasswordField { PasswordField }
import from .session { sign_in }

def:pub LoginPage -> JsxElement {
    nav = useNavigate();
    [email, set_email] = useState("");
    [password, set_password] = useState("");
    [busy, set_busy] = useState(False);
    [error, set_error] = useState("");
    if jacIsLoggedIn() {
        return <Navigate to="/app" replace={True}/>;
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
        outcome = await sign_in(email, password);
        set_busy(False);
        if outcome == "ok" {
            nav("/app");
        } elif outcome == "offline" {
            set_error(
                "We couldn't reach AfriCinemas. Check your connection and try again."
            );
        } else {
            set_error("Email or password is incorrect.");
        }
    }
    return
        <AuthLayout
            title="Sign in"
            description="Manage your cinema, staff and screenings."
            footer={<AuthFooter
                text="New to AfriCinemas?"
                to="/signup"
                label="Create an account"
            />}
        >
            <form onSubmit={submit} noValidate={True}>
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
