"""Settings → AI chat (P8.3): the cinema's own connector for AI chats such as Claude.

Shows the cinema's connector link (`connector_url`, served by core/mcp/server.jac as
POST /c/{slug}/mcp) with a Copy button and the three steps to add it in Claude. The
connector is read-only: customers see the cinema's programme, posters, trailers and
showtimes in the chat and book on the cinema's website. Copying falls back to selecting
the link when the browser won't copy.
"""

import from react { useState }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }

def:pub connector_url(origin: str, slug: str) -> str {
    # The cinema's own MCP connector, on the site the staff member is using.
    return f"{origin}/c/{slug}/mcp";
}

def:pub ConnectSection(slug: str, cinema: str) -> JsxElement {
    [copied, set_copied] = useState(False);
    [problem, set_problem] = useState("");
    win: any = window;  # jac:ignore[W1037,W2001]
    link = connector_url(win.location.origin, slug);

    async def copy_link {
        try {
            clip: any = navigator.clipboard;  # jac:ignore[W1037,W2001]
            await clip.writeText(link);
            set_copied(True);
            set_problem("");
        } except Exception as e {
            console.warn("copy failed", e);
            field: any = document.getElementById("connector-link");  # jac:ignore[W1037,W2001]
            if field {
                field.select();
            }
            set_problem(
                "Copy didn't work here: the link is selected, so copy it yourself."
            );
        }
    }

    steps = [
        "In Claude, open Settings, then Connectors, and choose Add custom connector.",
        f"Name it {cinema}, paste the link, and choose No sign-in.",
        f"In a new chat, turn the connector on and ask: What's on at {cinema}?"
    ];
    return
        <section
            data-testid="connect-section"
            aria-labelledby="connect-heading"
            className="flex max-w-2xl flex-col gap-6"
        >
            <div className="flex flex-col gap-2">
                <h2 id="connect-heading" className="text-xl font-semibold">
                    Your cinema in AI chats
                </h2>
                <p className="text-muted-foreground">
                    Customers who use an AI assistant such as Claude can add your cinema and ask what's on. They see your posters, trailers and showtimes in the chat, then book on your website.
                </p>
            </div>
            <div className="flex flex-col gap-2">
                <Label htmlFor="connector-link">Your connector link</Label>
                <div className="flex flex-wrap gap-2">
                    <Input
                        id="connector-link"
                        data-testid="connector-link"
                        value={link}
                        readOnly={True}
                        className="min-h-11 min-w-0 flex-1 basis-64 font-mono text-sm"
                    />
                    <Button
                        type="button"
                        data-testid="copy-connector"
                        className="min-h-11 px-5"
                        onClick={copy_link}
                    >
                        {"Copied" if copied else "Copy link"}
                    </Button>
                </div>
                <p aria-live="polite" className="text-sm text-muted-foreground">
                    {problem}
                </p>
            </div>
            <div className="flex flex-col gap-3">
                <h3 className="font-semibold">Add it in Claude</h3>
                <ol className="flex list-decimal flex-col gap-2 pl-5">
                    {[<li key={i}>{s}</li> for (i, s) in enumerate(steps)]}
                </ol>
            </div>
            <p className="text-sm text-muted-foreground">
                The connector only shows what your website already shows: your published showtimes that are on sale. Nobody can change anything through it, and it never shows your staff, sales or customers.
            </p>
        </section>;
}
