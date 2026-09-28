"""`/signup`: a cinema owner creates an account, then goes straight to the new-cinema
wizard at `/app/new`."""

import from react { useState }
import from "@jac/runtime" { Navigate, useNavigate, jacIsLoggedIn }
import from ...components.ui.button { Button }
import from ...components.ui.field { FieldGroup }
import from ...components.ui.spinner { Spinner }
import from .AuthLayout { AuthLayout, AuthFooter, EmailField, FormError }
import from .PasswordField { PasswordField }
import from .session { sign_up }

glob PASSWORD_MIN: int = 8;

def:pub SignupPage -> JsxElement {
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
        if "@" not in str(email) {
            set_error("Enter your email address, like name@example.com.");
            return;
        }
        if len(password) < PASSWORD_MIN {
            set_error(f"Choose a password of at least {PASSWORD_MIN} characters.");
            return;
        }
        set_busy(True);
        set_error("");
        problem: str = "";
        try {
            problem = await sign_up(email, password);
        } except Exception as err {
            console.warn("sign-up failed", err);
            problem = "We couldn't reach AfriCinemas. Check your connection and try again.";
        }
        set_busy(False);
        if problem {
            set_error(problem);
        } else {
            nav("/app/new");
        }
    }
    return
        <AuthLayout
            title="Create your account"
            description="Start selling tickets for your cinema in minutes."
            footer={<AuthFooter
                text="Already have an account?"
                to="/login"
                label="Sign in"
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
                        auto_complete="new-password"
                        hint={f"At least {PASSWORD_MIN} characters."}
                        min_length={PASSWORD_MIN}
                    />
                    <Button type="submit" disabled={busy} className="h-11 w-full">
                        {busy and <Spinner aria-hidden="true"/>}{"Creating your account…"
                            if busy
                            else "Create account"}
                    </Button>
                </FieldGroup>
            </form>
        </AuthLayout>;
}
