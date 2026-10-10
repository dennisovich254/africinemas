"""`/c/:slug/sign-in` and `/c/:slug/sign-up`: a cinema's own customer accounts (P8.6c).

A storefront is its own product (user decision 2026-10-10): its customers sign in and up
here, in the cinema's branding (the storefront's frame), with nothing of the back office.
The account is this cinema's alone (customer_session.jac). After signing in they go back
where they came from on this storefront, or to an app's consent page (Claude), else to
their tickets here.
"""

import from react { useState }
import from "@jac/runtime" { useNavigate, useParams }
import from ...components.ui.button { Button }
import from ...components.ui.field { FieldGroup }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from ..auth.AuthLayout { EmailField, FormError }
import from ..auth.PasswordField { PasswordField }
import from ..shell.AppLink { AppLink }
import from .StorefrontShell { StorefrontShell }
import from .customer_session {
    customer_sign_in,
    create_customer_account,
    back_to,
    asked_next
}

glob PASSWORD_MIN: int = 8,
     LINK: str = "font-medium underline underline-offset-4 hover:text-foreground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring";

def AuthCard(
    title: str,
    lead: str,
    children: any = None,  # jac:ignore[W1037]
    footer: any = None  # jac:ignore[W1037]
) -> JsxElement {
    return
        <div className="mx-auto flex w-full max-w-md flex-col gap-6 py-6">
            <div className="flex flex-col gap-2">
                <h1 className="font-display text-4xl leading-none">{title}</h1>
                <p className="text-muted-foreground">{lead}</p>
            </div>
            {children}
            {footer and <p className="text-sm text-muted-foreground">{footer}</p>}
        </div>;
}

def:pub CustomerSignInPage -> JsxElement {
    params: any = useParams();  # jac:ignore[W1037,W1051]
    slug: str = params["slug"] or "";
    nav: any = useNavigate();  # jac:ignore[W1037,W1051]
    [email, set_email] = useState("");
    [password, set_password] = useState("");
    [busy, set_busy] = useState(False);
    [error, set_error] = useState("");
    after = back_to(slug, asked_next());

    async def submit(e: any) {  # jac:ignore[W1037]
        e.preventDefault();
        if not email.strip() or not password {
            set_error("Enter your email and password.");
            return;
        }
        set_busy(True);
        set_error("");
        outcome = await customer_sign_in(slug, email, password);
        set_busy(False);
        if outcome == "ok" {
            nav(after);  # jac:ignore[W1051]
        } elif outcome == "offline" {
            set_error(
                "We couldn't reach the cinema. Check your connection and try again."
            );
        } else {
            set_error("Email or password is incorrect for an account at this cinema.");
        }
    }

    return
        <StorefrontShell slug={slug} chat={False}>
            <AuthCard
                title="Sign in"
                lead="Keep your tickets in one place and book faster."
                footer={<span>
                    {"New here? "}
                    <AppLink
                        to={f"/c/{slug}/sign-up?next={after}"}
                        testid="go-sign-up"
                        className={LINK}
                    >
                        Create an account
                    </AppLink>
                </span>}
            >
                <form
                    onSubmit={submit}
                    noValidate={True}
                    data-testid="customer-sign-in"
                >
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
            </AuthCard>
        </StorefrontShell>;
}

def:pub CustomerSignUpPage -> JsxElement {
    params: any = useParams();  # jac:ignore[W1037,W1051]
    slug: str = params["slug"] or "";
    nav: any = useNavigate();  # jac:ignore[W1037,W1051]
    [name, set_name] = useState("");
    [email, set_email] = useState("");
    [password, set_password] = useState("");
    [busy, set_busy] = useState(False);
    [error, set_error] = useState("");
    after = back_to(slug, asked_next());

    def typed_name(event: any) {  # jac:ignore[W1037]
        set_name(event.target.value);
    }

    async def submit(e: any) {  # jac:ignore[W1037]
        e.preventDefault();
        if not name.strip() or not email.strip() or not password {
            set_error("Enter your name, email and a password.");
            return;
        }
        if len(password) < PASSWORD_MIN {
            set_error(f"Use a password of at least {PASSWORD_MIN} characters.");
            return;
        }
        set_busy(True);
        set_error("");
        problem = await create_customer_account(slug, email, password, name);
        set_busy(False);
        if problem {
            set_error(problem);
            return;
        }
        nav(after);  # jac:ignore[W1051]
    }

    return
        <StorefrontShell slug={slug} chat={False}>
            <AuthCard
                title="Create your account"
                lead="Your account is for this cinema: your tickets, saved in one place."
                footer={<span>
                    {"Already have an account here? "}
                    <AppLink
                        to={f"/c/{slug}/sign-in?next={after}"}
                        testid="go-sign-in"
                        className={LINK}
                    >
                        Sign in
                    </AppLink>
                </span>}
            >
                <form
                    onSubmit={submit}
                    noValidate={True}
                    data-testid="customer-sign-up"
                >
                    <FieldGroup>
                        <FormError message={error}/>
                        <div className="flex flex-col gap-2">
                            <Label htmlFor="name">Your name</Label>
                            <Input
                                id="name"
                                value={name}
                                autoComplete="name"
                                maxLength={80}
                                onChange={typed_name}
                                className="min-h-11"
                            />
                        </div>
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
            </AuthCard>
        </StorefrontShell>;
}
