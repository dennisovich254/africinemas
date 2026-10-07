"""Where a paid order's tickets live, and getting them again (P6.3a).

Under the tickets on "You're booked" and on the tickets page: where they were emailed,
the private ticket link (open it, or copy it to keep), and Resend, to the same address
or a corrected one ("Use a different address"). The server allows three resends an
hour; past that it says so. Results are announced politely.
"""

import from react { useState }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from ..shell.AppLink { AppLink }
import from core.booking.ticket_delivery { resend_tickets }
import from .checkout_rules { email_problem }

def:pub TicketDelivery(link: str, email: str, show_open: bool) -> JsxElement {
    # link: "/c/<slug>/tickets/<token>"; email: the masked address they went to.
    parts: list[str] = link.split("/");
    slug: str = parts[2];
    token: str = parts[4];
    [sent_to, set_sent_to] = useState(email);
    [changing, set_changing] = useState(False);
    [address, set_address] = useState("");
    [address_error, set_address_error] = useState("");
    [busy, set_busy] = useState(False);
    [note, set_note] = useState("");
    shown_to: str = sent_to;
    is_changing: bool = changing;
    wrong: str = address_error;

    async def copy {
        win: any = window;  # jac:ignore[W1037,W2001]
        try {
            await win.navigator.clipboard.writeText(f"{win.location.origin}{link}");
            set_note("Link copied. Keep it to open your tickets any time.");
        } except Exception {
            set_note(f"Copy this link to keep it: {win.location.origin}{link}");
        }
    }

    async def resend(to: str) {
        set_busy(True);
        set_note("");
        try {
            done: any = await resend_tickets(slug, token, to);  # jac:ignore[W1037]
        } except Exception {
            done = None;
        }
        set_busy(False);
        if done is None {
            set_note(
                "We couldn't reach the cinema. Check your connection and try again."
            );
            return;
        }
        if done["ok"] {
            set_sent_to(done["email"]);
            set_changing(False);
            set_address("");
            set_note(f"Sent again to {done['email']}. It can take a minute to arrive.");
            return;
        }
        if done["error"]["code"] == "invalid_email" {
            set_address_error(done["error"]["message"]);
            return;
        }
        set_note(done["error"]["message"]);
    }

    def send_elsewhere(e: any) {  # jac:ignore[W1037]
        e.preventDefault();
        problem = email_problem(address);
        set_address_error(problem);
        if len(problem) == 0 {
            resend(address);
        }
    }

    change_form = is_changing
        and <form
            onSubmit={send_elsewhere}
            noValidate={True}
            data-testid="resend-elsewhere"
            className="flex flex-col gap-2"
        >
            <Label htmlFor="resend-email">Send them to</Label>
            <div className="flex flex-col gap-2 sm:flex-row">
                <Input
                    id="resend-email"
                    name="email"
                    type="email"
                    inputMode="email"
                    autoComplete="email"
                    placeholder="name@example.com"
                    value={address}
                    aria-invalid={"true" if len(wrong) > 0 else "false"}
                    aria-describedby={"resend-email-error" if len(wrong) > 0 else None}
                    onChange={lambda (e: any) { set_address(e.target.value); }}  # jac:ignore[W1037]
                    className="h-11 text-base sm:max-w-xs"
                />
                <Button
                    type="submit"
                    data-testid="resend-send"
                    disabled={busy}
                    className="min-h-11"
                >
                    {busy and <Spinner aria-hidden="true"/>}Send
                </Button>
            </div>
            {len(wrong) > 0
                and <p
                    id="resend-email-error"
                    data-testid="resend-email-error"
                    className="text-sm text-destructive"
                >
                    {wrong}
                </p>}
        </form>;

    return
        <div
            data-testid="ticket-delivery"
            className="flex flex-col gap-3 border-t pt-4"
        >
            {len(shown_to) > 0
                and <p className="text-sm" data-testid="sent-to">
                    {f"We've emailed your tickets to {shown_to}."}
                </p>}
            <div className="flex flex-wrap gap-2">
                {show_open
                    and <AppLink
                        to={link}
                        testid="open-tickets"
                        className="inline-flex min-h-11 items-center rounded-md border px-4 text-sm font-medium hover:bg-muted"
                    >
                        Open your tickets page
                    </AppLink>}
                <Button
                    variant="outline"
                    data-testid="copy-link"
                    onClick={lambda { copy(); }}
                    className="min-h-11"
                >
                    Copy link
                </Button>
                <Button
                    variant="outline"
                    data-testid="resend"
                    disabled={busy}
                    onClick={lambda { resend(""); }}
                    className="min-h-11"
                >
                    {busy
                        and not is_changing
                        and <Spinner aria-hidden="true"/>}Resend email
                </Button>
                {not is_changing
                    and <Button
                        variant="ghost"
                        data-testid="change-email"
                        onClick={lambda { set_changing(True); }}
                        className="min-h-11"
                    >
                        Use a different address
                    </Button>}
            </div>
            {change_form}
            <p
                role="status"
                aria-live="polite"
                data-testid="delivery-note"
                className="text-sm text-muted-foreground"
            >
                {note}
            </p>
        </div>;
}
