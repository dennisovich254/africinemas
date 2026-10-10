"""`/login`: staff sign in with their email and password, then pick a cinema at `/app`."""

import from react { useState }
import from "@jac/runtime" { Navigate, useNavigate }
import from ...components.ui.button { Button }
import from ...components.ui.field { FieldGroup }
import from ...components.ui.spinner { Spinner }
import from .AuthLayout { AuthLayout, AuthFooter, EmailField, FormError }
import from .PasswordField { PasswordField }
import from .session { sign_in, next_path, use_staff_session }

def:pub LoginPage -> JsxElement {
    nav: any = useNavigate();  # jac:ignore[W1037,W1051]
    [email, set_email] = useState("");
    [password, set_password] = useState("");
    [busy, set_busy] = useState(False);
    [error, set_error] = useState("");
    # After signing in: back to the invitation that sent them here, else their cinemas.
    after = next_path() or "/app";
    # A customer account (a cinema's storefront, P8.6c) isn't one of ours: sign in here
    # with a staff account instead.
    session = use_staff_session();
    if session == "staff" {
        return <Navigate to={after} replace={True}/>;
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
            nav(after);
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
                to={"/signup?next=" + after if after != "/app" else "/signup"}
                label="Create an account"
            />}
        >
            <form onSubmit={submit} noValidate={True}>
                <FieldGroup>
                    <FormError
                        message={error
                            or (
                                "You're signed in to a cinema's website as a customer. Sign in here with your staff account."
                                    if session == "customer"
                                    else ""
                            )}
                    />
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
