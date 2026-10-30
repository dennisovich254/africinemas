"""Settings → Box office (`/app/:slug/settings/box-office`, P15.6b).

How long a box office shift lasts (8 hours unless changed, 1 to 12), the most one cash
count may be (KES 500,000 unless changed), and how long before a showtime its unsold
counter seats go on sale online (2 hours unless changed, 0 to 72; 2026-10-30). For those who change the cinema's settings
(tenant.settings.update: owners, cinema admins and IT admins); a shift already open
keeps its length.
"""

import from react { useState, useEffect }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.tenancy.tenant_api {
    box_office_rules,  # jac:ignore[W2037] authenticated endpoint
    set_box_office_rules,  # jac:ignore[W2037] authenticated endpoint
    set_counter_release_hours  # jac:ignore[W2037] authenticated endpoint
}
import from .PricesSection { cents_of }
import from .form_parts { on_input }

def:pub BoxOfficeRules(slug: str) -> JsxElement {
    [hours, set_hours] = useState("");
    [most, set_most] = useState("");
    [release, set_release] = useState("");
    [ready, set_ready] = useState(False);
    [busy, set_busy] = useState(False);
    [said, set_said] = useState("");
    [problem, set_problem] = useState("");

    def show(got: any) {  # jac:ignore[W1037]
        set_hours(str(got["shift_hours"]));
        set_most(str(int(int(got["cash_count_max_cents"]) / 100)));
        set_release(str(got["counter_release_hours"]));
        set_ready(True);
    }

    async def load {
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await box_office_rules(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("box_office_rules failed", e);
        }
        if got is not None and got["ok"] {
            show(got);
        } else {
            set_problem("We couldn't load these. Reload the page to try again.");
        }
    }

    def start {
        load();
    }
    useEffect(start, [slug]);

    async def save(e: any) {  # jac:ignore[W1037]
        e.preventDefault();
        set_said("");
        set_problem("");
        cents: any = cents_of(most, False);  # jac:ignore[W1037]
        typed: str = hours.strip();
        typed_release: str = release.strip();
        if cents is None or len(typed) == 0 or len(typed_release) == 0 {
            set_problem("Enter the hours and the amount.");
            return;
        }
        set_busy(True);
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await set_box_office_rules(slug, int(typed), cents);  # jac:ignore[W2037]
            if got is not None and got["ok"] {
                got = await set_counter_release_hours(slug, int(typed_release));  # jac:ignore[W2037]
            }
        } except Exception as err {
            console.warn("set_box_office_rules failed", err);
        }
        set_busy(False);
        if got is None or not got["ok"] {
            set_problem(
                got["error"]["message"]
                    if got is not None
                    else "We couldn't save that. Try again."
            );
            return;
        }
        show(got);
        set_said("Saved. New shifts use these rules.");
    }

    if not ready and not problem {
        return <Spinner aria-label="Loading"/>;
    }
    return
        <form
            className="flex max-w-xl flex-col gap-4 rounded-lg border bg-card p-4"
            data-testid="box-office-rules"
            onSubmit={save}
        >
            <div className="flex flex-col gap-1.5">
                <Label htmlFor="shift-hours">Shift length (hours)</Label>
                <Input
                    id="shift-hours"
                    inputMode="numeric"
                    value={hours}
                    onChange={on_input(set_hours)}
                    aria-describedby="shift-hours-help"
                    className="min-h-11 max-w-32"
                />
                <p id="shift-hours-help" className="text-sm text-muted-foreground">
                    From 1 to 12. A shift ends when its member counts their cash, or after this long if they don't; cash they didn't count is shown on Reconciliation.
                </p>
            </div>
            <div className="flex flex-col gap-1.5">
                <Label htmlFor="cash-count-max">Largest cash count (KES)</Label>
                <Input
                    id="cash-count-max"
                    inputMode="decimal"
                    value={most}
                    onChange={on_input(set_most)}
                    aria-describedby="cash-count-max-help"
                    className="min-h-11 max-w-48"
                />
                <p id="cash-count-max-help" className="text-sm text-muted-foreground">
                    From KES 1,000 to KES 10,000,000. A count above it is refused, to catch a slip like an extra zero.
                </p>
            </div>
            <div className="flex flex-col gap-1.5">
                <Label htmlFor="counter-release">
                    Counter seats go on sale online (hours before the show)
                </Label>
                <Input
                    id="counter-release"
                    inputMode="numeric"
                    value={release}
                    onChange={on_input(set_release)}
                    aria-describedby="counter-release-help"
                    className="min-h-11 max-w-32"
                />
                <p id="counter-release-help" className="text-sm text-muted-foreground">
                    From 0 to 72. Seats you keep for the counter (on each screen's page) can be booked online once it's this close to the showtime, so none go empty. 0 keeps them for the counter until the show starts.
                </p>
            </div>
            <div>
                <Button type="submit" className="min-h-11" disabled={busy}>
                    {"Saving…" if busy else "Save"}
                </Button>
            </div>
            <p role="status" className="text-sm empty:hidden">{said}</p>
            <p role="alert" className="text-sm text-destructive empty:hidden">
                {problem}
            </p>
        </form>;
}
