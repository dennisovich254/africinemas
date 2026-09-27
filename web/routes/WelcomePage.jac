"""`/`: the storefront welcome card (P0.8b). The storefront screens replace it in P4."""

import from ...components.ui.button { Button }
import from ...components.ui.card {
    Card,
    CardHeader,
    CardTitle,
    CardDescription,
    CardContent
}
import from ..theme.ThemeProvider { ThemeProvider }

def:pub WelcomePage -> JsxElement {
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
