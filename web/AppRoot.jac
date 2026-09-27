"""Root UI component shared by the web app and the desktop app.

Both entry points (main.jac and desktop/main.jac) render <AppRoot />, so every
screen is written once. See docs/adr/0001-desktop-reuses-web-ui.md.
"""

import from ..components.ui.button { Button }
import from ..components.ui.card {
    Card,
    CardHeader,
    CardTitle,
    CardDescription,
    CardContent
}
import from .theme.ThemeProvider { ThemeProvider }

def:pub AppRoot -> JsxElement {
    return
        <ThemeProvider surface="storefront">
            <main className="min-h-svh flex items-center justify-center p-4 sm:p-6">
                <Card className="w-full max-w-md" data-testid="welcome-card">
                    <CardHeader>
                        <CardTitle
                            className="font-display text-5xl leading-none"
                            data-testid="wordmark"
                        >
                            AfriCinemas
                        </CardTitle>
                        <CardDescription>
                            Cinema tickets, booked in seconds.
                        </CardDescription>
                    </CardHeader>
                    <CardContent className="flex flex-col gap-3 sm:flex-row">
                        <Button className="min-h-11" data-testid="primary-cta">
                            Browse movies
                        </Button>
                        <Button
                            variant="outline"
                            className="min-h-11"
                            data-testid="secondary-cta"
                        >
                            Cinema owners
                        </Button>
                    </CardContent>
                </Card>
            </main>
        </ThemeProvider>;
}
