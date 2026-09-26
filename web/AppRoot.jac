"""Root UI component shared by the web app and the desktop app.

Both entry points (main.jac and desktop/main.jac) render <AppRoot />, so every
screen is written once. See docs/adr/0001-desktop-reuses-web-ui.md.
"""

import from ..components.ui.button { Button }
import from ..components.ui.card {
    Card, CardHeader, CardTitle, CardDescription, CardContent
}

def:pub AppRoot -> JsxElement {
    return <div className="min-h-screen bg-background text-foreground flex items-center justify-center p-6">
        <Card className="w-full max-w-md">
            <CardHeader>
                <CardTitle>AfriCinemas</CardTitle>
                <CardDescription>Cinema tickets, booked in seconds.</CardDescription>
            </CardHeader>
            <CardContent className="flex gap-2">
                <Button>Browse movies</Button>
                <Button variant="outline">Cinema owners</Button>
            </CardContent>
        </Card>
    </div>;
}
