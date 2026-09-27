"""Catch-all route: a plain not-found page with a way home."""

import from "@jac/runtime" { Link }
import from ...components.ui.button { Button }
import from ..theme.ThemeProvider { ThemeProvider }

def:pub NotFoundPage -> JsxElement {
    return
        <ThemeProvider surface="storefront">
            <main
                className="min-h-svh flex flex-col items-center justify-center gap-4 p-4 text-center"
                data-testid="not-found"
            >
                <h1 className="font-display text-5xl leading-none">Page not found</h1>
                <p className="text-muted-foreground">
                    This page doesn't exist or has moved.
                </p>
                <Button asChild={True} className="min-h-11 px-5">
                    <Link to="/">Back to home</Link>
                </Button>
            </main>
        </ThemeProvider>;
}
