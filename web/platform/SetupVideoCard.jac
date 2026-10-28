"""The M-Pesa setup video, on the console's Fees page (P15.3).

Platform staff see the link every cinema's Settings -> Payments plays; a super admin
(platform.settings) pastes a new one (a YouTube link plays on the page; any other https
link opens in a new tab) or clears it (core/payments/setup_help.jac).
"""

import from react { useState, useEffect }
import from ...components.ui.button { Button }
import from core.payments.setup_help {
    mpesa_guide_video,  # jac:ignore[W2037] authenticated endpoint
    set_mpesa_guide_video  # jac:ignore[W2037] authenticated endpoint
}
import from .FeesPage { RateField }

def:pub SetupVideoCard(may_change: bool = False) -> JsxElement {
    [video, set_video] = useState(None);
    [url, set_url] = useState("");
    [busy, set_busy] = useState(False);
    [note, set_note] = useState("");

    async def load {
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await mpesa_guide_video();  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("mpesa_guide_video failed", e);
        }
        if got is not None and got["ok"] {
            set_video(got["video"]);
            set_url(got["video"]["url"]);
        }
    }

    def start {
        load();
    }
    useEffect(start, []);

    async def save(e: any) {  # jac:ignore[W1037]
        e.preventDefault();
        set_busy(True);
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await set_mpesa_guide_video(url);  # jac:ignore[W2037]
        } except Exception as err {
            console.warn("set_mpesa_guide_video failed", err);
        }
        set_busy(False);
        if got is None or not got["ok"] {
            set_note(
                got["error"]["message"]
                    if got is not None
                    else "We couldn't save that. Try again."
            );
            return;
        }
        set_video(got["video"]);
        set_note(
            "Saved. Cinemas see it on Settings → Payments."
                if got["video"]["url"]
                else "Cleared. Cinemas see only the written steps."
        );
    }

    shown: dict[str, str] | None = video;  # jac:ignore[W1037]
    return
        <section
            data-testid="setup-video"
            className="flex flex-col gap-3 rounded-lg border bg-card p-4"
        >
            <h2 className="text-lg font-semibold">M-Pesa setup video</h2>
            <p className="text-sm text-muted-foreground">
                Shown to cinemas above the steps for getting their Daraja keys. A YouTube link plays on the page; record it unlisted.
            </p>
            {shown is not None
                and not may_change
                and <p className="text-sm break-all">
                    {shown["url"] or "No video yet."}
                </p>}
            {may_change
                and <form className="flex flex-col gap-3" onSubmit={save}>
                    <RateField
                        field_id="setup-video-url"
                        label="Video link (leave empty for none)"
                        value={url}
                        on_value={set_url}
                        kind="url"
                    />
                    <div>
                        <Button type="submit" disabled={busy} className="min-h-11">
                            {"Saving…" if busy else "Save link"}
                        </Button>
                    </div>
                    <p
                        role="status"
                        aria-live="polite"
                        className="text-sm empty:hidden"
                    >
                        {note}
                    </p>
                </form>}
        </section>;
}
