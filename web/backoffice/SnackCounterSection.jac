"""`/app/:slug/snack-counter`: handing over snacks bought with tickets (P12.9; ADR-0053).

Staff scan the customer's pickup code with the camera (the scanner's Camera, P6.4) or
type its reference, and the page shows the order (snack_pickup): its showtime, each
snack with its extras and a combo's contents, and whether it can be handed over now. Hand
over (hand_over_snacks) marks it collected, once; a refusal says why in words, such as
when they were already handed over and by whom, or when pickup opens. "Next order"
clears the page for the next customer.
"""

import from react { useState }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.badge { Badge }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.snacks.pickup_api { snack_pickup, hand_over_snacks }  # jac:ignore[W2037] authenticated endpoints
import from ..storefront.showtimes { time_label, long_day_label }
import from .ScannerSection { Camera }
import from .form_parts { on_input, submit_with }

def:pub refusal_text(answer: dict[str, any], tz: str) -> str {  # jac:ignore[W1037]
    # A refusal in words for the person at the counter.
    error: dict[str, any] = answer["error"];  # jac:ignore[W1037]
    code: str = error["code"];
    if code == "already_collected" {
        return f"Already handed over at {time_label(error['collected_at'], tz)} by {error[
            'collected_by'
        ]}.";
    }
    if code == "too_early" {
        return f"Too early: snacks for this showtime can be collected from {time_label(
            error['opens_at'], tz
        )}.";
    }
    return error["message"];
}

def:pub SnackCounterSection(slug: str, shift_open: bool = True) -> JsxElement {
    [typed, set_typed] = useState("");
    [code, set_code] = useState("");
    [pickup, set_pickup] = useState(None);
    [problem, set_problem] = useState("");
    [done, set_done] = useState("");
    [busy, set_busy] = useState(False);

    async def look_up(given: str) {
        wanted = given.strip();
        if not wanted or busy {
            return;
        }
        set_busy(True);
        set_problem("");
        set_done("");
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await snack_pickup(slug, wanted);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("snack_pickup failed", e);
        }
        set_busy(False);
        if answer is None {
            set_problem(
                "We couldn't reach the server. Check the connection and try again."
            );
            return;
        }
        if not answer["ok"] {
            set_pickup(None);
            set_problem(refusal_text(answer, ""));
            return;
        }
        set_code(wanted);
        set_pickup(answer["pickup"]);
    }

    async def hand_over {
        shown: dict[str, any] = pickup;  # jac:ignore[W1037]
        set_busy(True);
        set_problem("");
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await hand_over_snacks(slug, code, shown["collection_token"]);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("hand_over_snacks failed", e);
        }
        set_busy(False);
        if answer is None {
            set_problem(
                "We couldn't reach the server. Check the connection and try again."
            );
            return;
        }
        if not answer["ok"] {
            set_problem(refusal_text(answer, shown["timezone"]));
            return;
        }
        set_pickup(answer["pickup"]);
        set_done("Handed over. Enjoy the show!");
    }

    def next_order {
        set_typed("");
        set_code("");
        set_pickup(None);
        set_problem("");
        set_done("");
    }

    def scanned(text: str) {
        set_typed(text);
        look_up(text);
    }

    if not shift_open {
        return
            <p className="text-sm text-muted-foreground">
                Start your shift to hand over snacks.
            </p>;
    }
    shown: dict[str, any] | None = pickup;  # jac:ignore[W1037]
    return
        <div className="flex max-w-2xl flex-col gap-6" data-testid="snack-counter">
            <p className="text-sm text-muted-foreground">
                Scan the customer's snack pickup code, or type it. Check the snacks, then hand them over.
            </p>
            <Camera on_code={scanned} screening_id="counter" typed="the pickup code"/>
            <form
                className="flex flex-col gap-1.5"
                onSubmit={submit_with(lambda { look_up(typed); })}
            >
                <Label htmlFor="pickup-code">Pickup code</Label>
                <div className="flex flex-wrap gap-2">
                    <Input
                        id="pickup-code"
                        data-testid="pickup-code"
                        value={typed}
                        autoComplete="off"
                        autoCapitalize="characters"
                        placeholder="e.g. 7K2M-9QXR-4HJN-P3WD"
                        onChange={on_input(set_typed)}
                        className="min-h-11 min-w-0 flex-1 font-mono"
                    />
                    <Button
                        type="submit"
                        variant="outline"
                        className="min-h-11 px-5"
                        disabled={busy or not typed.strip()}
                        data-testid="look-up"
                    >
                        Look up
                    </Button>
                </div>
            </form>
            {problem
                and <Alert
                    variant="destructive"
                    role="alert"
                    data-testid="counter-problem"
                >
                    <AlertDescription>{problem}</AlertDescription>
                </Alert>}
            {shown is not None
                and <section
                    aria-labelledby="pickup-heading"
                    data-testid="pickup"
                    className="flex flex-col gap-4 rounded-lg border bg-card p-4"
                >
                    <div className="flex flex-wrap items-start justify-between gap-3">
                        <div className="flex flex-col gap-1">
                            <h2 id="pickup-heading" className="text-lg font-semibold">
                                {shown["movie_title"] or "Snack order"}
                            </h2>
                            <p className="text-sm text-muted-foreground">
                                {f"{long_day_label(
                                    shown['starts_at'], shown['timezone']
                                )} · {time_label(
                                    shown['starts_at'], shown['timezone']
                                )} · {shown['venue']} · Order {shown[
                                    'order_reference'
                                ]}"
                                    if shown["starts_at"]
                                    else f"Order {shown['order_reference']}"}
                            </p>
                        </div>
                        <Badge
                            data-testid="pickup-state"
                            variant={"default"
                                if shown["collected_at"]
                                else (
                                    "outline"
                                        if shown["window"] == "open"
                                        else "secondary"
                                )}
                        >
                            {(
                                "Handed over"
                                    if shown["collected_at"]
                                    else (
                                        "Not paid"
                                            if not shown["paid"]
                                            else (
                                                "Ready to hand over"
                                                    if shown["window"] == "open"
                                                    else (
                                                        "Too early"
                                                            if shown["window"]
                                                                == "early"
                                                            else "Showtime ended"
                                                    )
                                            )
                                    )
                            )}
                        </Badge>
                    </div>
                    <ul className="flex flex-col divide-y" data-testid="pickup-snacks">
                        {[
                            <li
                                key={f"line-{n}"}
                                className="flex flex-col gap-0.5 py-2"
                            >
                                <span className="font-medium">
                                    {f"{s['quantity']} × {s['name']}"}
                                </span>
                                {len(s["addons"]) > 0
                                    and <span className="text-sm text-muted-foreground">
                                        {"With " + ", ".join(s["addons"])}
                                    </span>}
                                {len(s["choices"]) > 0
                                    and <span className="text-sm text-muted-foreground">
                                        {"Includes " + ", ".join(s["choices"])}
                                    </span>}
                            </li> for (n, s) in enumerate(shown["snacks"])
                        ]}
                    </ul>
                    {len(shown["collected_snacks"] or []) > 0
                        and <div
                            className="text-sm text-muted-foreground"
                            data-testid="previous-snacks"
                        >
                            <p className="font-medium">Already collected</p>
                            <ul>
                                {[
                                    <li key={f"{i}"}>
                                        {f"{s['quantity']} × {s['name']}"}
                                    </li>
                                    for (i, s) in enumerate(shown["collected_snacks"])
                                ]}
                            </ul>
                        </div>}
                    {shown["collected_at"]
                        and <p className="text-sm" data-testid="pickup-collected">
                            {f"Handed over at {time_label(
                                shown['collected_at'], shown['timezone']
                            )} by {shown['collected_by']}."}
                        </p>}
                    {shown["window"] == "early"
                        and not shown["collected_at"]
                        and <p className="text-sm text-muted-foreground">
                            {f"Snacks for this showtime can be collected from {time_label(
                                shown['opens_at'], shown['timezone']
                            )}."}
                        </p>}
                    <p
                        role="status"
                        aria-live="polite"
                        className="text-sm font-medium empty:hidden"
                        data-testid="counter-done"
                    >
                        {done}
                    </p>
                    <div className="flex flex-wrap gap-2">
                        {not shown["collected_at"]
                            and <Button
                                className="min-h-11 px-5"
                                data-testid="hand-over"
                                disabled={busy
                                    or not shown["paid"]
                                    or shown["window"] != "open"}
                                onClick={hand_over}
                            >
                                {busy and <Spinner aria-hidden="true"/>}Hand over
                            </Button>}
                        <Button
                            variant="outline"
                            className="min-h-11 px-5"
                            data-testid="next-order"
                            onClick={next_order}
                        >
                            Next order
                        </Button>
                    </div>
                </section>}
        </div>;
}
