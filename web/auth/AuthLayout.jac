"""The frame around the sign-in and sign-up forms (the wordmark and one centred card, in
the back-office theme), and the fields and error message they share."""

import from react { useEffect, useRef }
import from "@jac/runtime" { Link }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { AlertCircleIcon }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.field { Field, FieldLabel }
import from ...components.ui.input { Input }
import from ...components.ui.card { Card, CardHeader, CardDescription, CardContent }
import from ..theme.ThemeProvider { ThemeProvider }

# `children` and `footer` are pass-through JSX (jac-cl-organization idiom).
def:pub AuthLayout(
    title: str,
    description: str,
    children: any = None,  # jac:ignore[W1037]
    footer: any = None  # jac:ignore[W1037]
) -> JsxElement {
    return
        <ThemeProvider surface="backoffice">
            <main
                className="flex min-h-svh flex-col items-center justify-center gap-6 px-4 py-10"
            >
                <Link
                    to="/"
                    className="font-display inline-flex min-h-11 items-center text-4xl leading-none"
                >
                    AfriCinemas
                </Link>
                <Card className="w-full max-w-sm">
                    <CardHeader>
                        <h1 className="text-xl font-semibold">{title}</h1>
                        <CardDescription>{description}</CardDescription>
                    </CardHeader>
                    <CardContent>{children}</CardContent>
                </Card>
                {footer}
            </main>
        </ThemeProvider>;
}

# `on_change` receives the new value (a string).
def:pub EmailField(value: str, on_change: any) -> JsxElement {  # jac:ignore[W1037]
    return
        <Field>
            <FieldLabel htmlFor="email">Email</FieldLabel>
            <Input
                id="email"
                name="email"
                type="email"
                inputMode="email"
                autoComplete="email"
                spellCheck={False}
                required={True}
                value={value}
                onChange={lambda (e: any) { on_change(e.target.value); }}  # jac:ignore[W1037]
                className="h-11 text-base"
            />
        </Field>;
}

# The form-level error: announced when it appears, and focused so keyboard and screen
# reader users land on it.
def:pub FormError(message: str) -> JsxElement {
    box = useRef(None);
    useEffect(lambda { if message and box.current { box.current.focus(); }}, [message]);
    if not message {
        return <div aria-live="assertive"/>;
    }
    return
        <Alert variant="destructive" data-testid="auth-error" tabIndex={-1} ref={box}>
            <HugeiconsIcon icon={AlertCircleIcon} strokeWidth={2} aria-hidden="true"/>
            <AlertDescription>{message}</AlertDescription>
        </Alert>;
}

def:pub AuthFooter(text: str, to: str, label: str) -> JsxElement {
    return
        <p className="text-sm text-muted-foreground">
            {text}{" "}
            <Link
                to={to}
                className="inline-flex min-h-11 min-w-11 items-center justify-center font-medium text-foreground underline underline-offset-4"
            >
                {label}
            </Link>
        </p>;
}
