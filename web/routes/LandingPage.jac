"""`/`: the AfriCinemas landing page (P3.9), replacing the P0.8b welcome card.

What AfriCinemas does, how it works, what a cinema gets and who it's for, with "Create
your cinema" (sign-up) and "Sign in". Signed-in staff see the same page, with a link to
their cinemas instead of "Sign in". The product glimpse is drawn from the platform theme
itself (the storefront tokens, light and dark), not stock art. The words come from
landing_content.jac. The theme tests (e2e/theme_tests.jac) read the primary-cta,
secondary-cta and wordmark test ids.
"""

import from "@jac/runtime" { jacIsLoggedIn }
import from ...components.ui.button { Button }
import from ..theme.ThemeProvider { ThemeProvider }
import from ..shell.AppLink { AppLink }
import from .landing_content {
    HERO,
    GLIMPSE,
    STEPS,
    FEATURES,
    AUDIENCE,
    CLOSING,
    FOOTER
}

glob WIDTH: str = "mx-auto w-full max-w-6xl px-4 sm:px-6",
     # The glimpse's seat rows: A = available, S = selected, X = sold, " " = aisle.
     SEAT_ROWS: list[str] = ["AAXX AAAA", "AAAA SSAA", "XAAA AAXA"];

def seat_class(kind: str) -> str {
    if kind == "S" {
        return "size-4 rounded-t-[5px] rounded-b-[2px] bg-[var(--ac-seat-selected)]";
    }
    if kind == "X" {
        return "size-4 rounded-t-[5px] rounded-b-[2px] bg-[var(--ac-seat-sold)]";
    }
    if kind == " " {
        return "size-4";
    }
    return "size-4 rounded-t-[5px] rounded-b-[2px] border-2 border-[var(--ac-seat-available)]";
}

def ProductGlimpse -> JsxElement {
    # A small storefront, in the platform's own storefront colours.
    return
        <figure data-testid="product-glimpse" className="flex flex-col gap-3">
            <div
                aria-hidden="true"
                className="flex flex-col gap-4 rounded-xl border bg-card p-4 sm:p-5"
            >
                <div className="flex items-center justify-between">
                    <span className="font-display text-2xl leading-none">
                        {GLIMPSE["cinema"]}
                    </span>
                    <span className="text-xs text-muted-foreground">Westgate</span>
                </div>
                <div className="flex gap-3">
                    <span
                        className="aspect-[2/3] w-16 shrink-0 rounded-md bg-[var(--ac-raised)]"
                    ></span>
                    <span className="flex min-w-0 flex-col gap-1">
                        <span className="font-display text-xl leading-none">
                            {GLIMPSE["film"]}
                        </span>
                        <span className="text-xs text-muted-foreground">
                            {GLIMPSE["facts"]}
                        </span>
                        <span className="mt-1 flex flex-wrap gap-1.5">
                            <span
                                className="rounded-md border px-2 py-0.5 text-xs font-medium"
                            >
                                14:30
                            </span>
                            <span
                                className="rounded-md bg-primary px-2 py-0.5 text-xs font-medium text-primary-foreground"
                            >
                                18:15
                            </span>
                            <span
                                className="rounded-md border px-2 py-0.5 text-xs font-medium"
                            >
                                21:00
                            </span>
                        </span>
                    </span>
                </div>
                <div className="flex flex-col items-center gap-1.5">
                    <span
                        className="h-1 w-3/4 rounded-full bg-[var(--ac-accent)] opacity-70"
                    ></span>
                    <span
                        className="text-[10px] tracking-[0.3em] text-muted-foreground"
                    >
                        SCREEN
                    </span>
                    {[
                        <span key={i} className="flex gap-1.5">
                            {[
                                <span key={j} className={seat_class(k)}></span>
                                for (j, k) in enumerate(row)
                            ]}
                        </span> for (i, row) in enumerate(SEAT_ROWS)
                    ]}
                </div>
                <div className="flex items-center justify-between gap-3 border-t pt-3">
                    <span className="text-xs text-muted-foreground">
                        {GLIMPSE["total"]}
                    </span>
                    <span
                        className="rounded-md bg-primary px-3 py-2 text-sm font-semibold text-primary-foreground"
                    >
                        {GLIMPSE["pay"]}
                    </span>
                </div>
            </div>
            <figcaption className="text-sm text-muted-foreground">
                {GLIMPSE["label"]}
            </figcaption>
        </figure>;
}

def:pub LandingPage -> JsxElement {
    signed_in = jacIsLoggedIn();
    account = (
        <AppLink
            to="/app"
            className="inline-flex min-h-11 items-center px-2 text-sm font-medium underline underline-offset-4"
        >
            {HERO["signed_in"]}
        </AppLink>
            if signed_in
            else <AppLink
                to="/login"
                className="inline-flex min-h-11 items-center px-2 text-sm font-medium underline underline-offset-4"
            >
                {HERO["sign_in"]}
            </AppLink>
    );
    return
        <ThemeProvider surface="storefront">
            <div data-testid="landing" className="flex min-h-svh flex-col">
                <header className="border-b">
                    <div
                        className={WIDTH
                            + " flex h-16 items-center justify-between gap-4"}
                    >
                        <span
                            data-testid="wordmark"
                            className="font-display text-3xl leading-none"
                        >
                            AfriCinemas
                        </span>
                        {account}
                    </div>
                </header>
                <main className="flex flex-1 flex-col gap-20 pb-20">
                    <section
                        aria-labelledby="hero-heading"
                        className={WIDTH
                            + " grid items-center gap-10 pt-12 lg:grid-cols-[1.1fr_1fr] lg:pt-20"}
                    >
                        <div className="flex flex-col gap-6">
                            <h1
                                id="hero-heading"
                                className="font-display text-5xl leading-[0.95] text-balance sm:text-6xl"
                            >
                                {HERO["title"]}
                            </h1>
                            <p className="max-w-xl text-lg text-muted-foreground">
                                {HERO["lead"]}
                            </p>
                            <div className="flex flex-wrap gap-3">
                                <Button asChild={True} className="min-h-11 px-6">
                                    <AppLink to="/signup" testid="primary-cta">
                                        {HERO["cta"]}
                                    </AppLink>
                                </Button>
                                <Button
                                    asChild={True}
                                    variant="outline"
                                    className="min-h-11 px-6"
                                >
                                    <AppLink
                                        to={"/app" if signed_in else "/login"}
                                        testid="secondary-cta"
                                    >
                                        {HERO["signed_in"]
                                            if signed_in
                                            else HERO["sign_in"]}
                                    </AppLink>
                                </Button>
                            </div>
                        </div>
                        <ProductGlimpse/>
                    </section>
                    <section
                        aria-labelledby="how-heading"
                        className={WIDTH + " flex flex-col gap-6"}
                    >
                        <h2
                            id="how-heading"
                            className="font-display text-4xl leading-none"
                        >
                            How it works
                        </h2>
                        <ol
                            data-testid="how-it-works"
                            className="grid gap-6 sm:grid-cols-2 lg:grid-cols-4"
                        >
                            {[
                                <li key={s["title"]} className="flex flex-col gap-2">
                                    <span
                                        aria-hidden="true"
                                        className="font-display text-4xl leading-none text-[var(--ac-accent-ink)]"
                                    >
                                        {str(i + 1)}
                                    </span>
                                    <h3 className="font-semibold">{s["title"]}</h3>
                                    <p className="text-sm text-muted-foreground">
                                        {s["text"]}
                                    </p>
                                </li> for (i, s) in enumerate(STEPS)
                            ]}
                        </ol>
                    </section>
                    <section
                        aria-labelledby="features-heading"
                        className={WIDTH + " flex flex-col gap-6"}
                    >
                        <h2
                            id="features-heading"
                            className="font-display text-4xl leading-none"
                        >
                            What your cinema gets
                        </h2>
                        <ul
                            className="grid gap-x-8 gap-y-6 sm:grid-cols-2 lg:grid-cols-3"
                        >
                            {[
                                <li
                                    key={f["title"]}
                                    className="flex flex-col gap-1 border-t pt-4"
                                >
                                    <h3 className="font-semibold">{f["title"]}</h3>
                                    <p className="text-sm text-muted-foreground">
                                        {f["text"]}
                                    </p>
                                </li> for f in FEATURES
                            ]}
                        </ul>
                    </section>
                    <section
                        aria-labelledby="audience-heading"
                        className={WIDTH + " flex flex-col gap-6"}
                    >
                        <h2
                            id="audience-heading"
                            className="font-display text-4xl leading-none"
                        >
                            Who it's for
                        </h2>
                        <ul
                            data-testid="audience"
                            className="grid gap-4 lg:grid-cols-3"
                        >
                            {[
                                <li
                                    key={a["title"]}
                                    className="flex flex-col gap-2 rounded-lg border bg-card p-5"
                                >
                                    <h3 className="font-semibold">{a["title"]}</h3>
                                    <p className="text-sm text-muted-foreground">
                                        {a["text"]}
                                    </p>
                                </li> for a in AUDIENCE
                            ]}
                        </ul>
                    </section>
                    <section aria-labelledby="closing-heading" className={WIDTH}>
                        <div
                            className="flex flex-col items-start gap-4 rounded-xl border bg-card p-6 sm:flex-row sm:items-center sm:justify-between sm:p-8"
                        >
                            <div className="flex flex-col gap-1">
                                <h2
                                    id="closing-heading"
                                    className="font-display text-4xl leading-none"
                                >
                                    {CLOSING["title"]}
                                </h2>
                                <p className="text-muted-foreground">
                                    {CLOSING["text"]}
                                </p>
                            </div>
                            <Button asChild={True} className="min-h-11 shrink-0 px-6">
                                <AppLink to="/signup">{CLOSING["cta"]}</AppLink>
                            </Button>
                        </div>
                    </section>
                </main>
                <footer className="border-t">
                    <p className={WIDTH + " py-6 text-sm text-muted-foreground"}>
                        {FOOTER}
                    </p>
                </footer>
            </div>
        </ThemeProvider>;
}
