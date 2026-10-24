"""The setup guide (improvements #4): a new cinema is walked through setting up, one step
after the other.

Above every back-office page, staff who set the cinema up (venues.configure) see the
next step to do: "Step 2 of 7", what it is, a line on how, and a button to the section
that does it (or a note that they're on it). It asks setup_steps again on every page
change, and every POLL_MS, so finishing a step moves it on. Once every step is done it
goes away.

"Hide the guide" is remembered on this device, per cinema; the Overview's checklist
offers to bring it back. Every component that asks (use_guide_hidden) hears the change
through a window event, as the storefront's venue choice does (venue_choice.jac).
"""

import from react { useState, useEffect }
import from ...components.ui.button { Button }
import from core.reporting.staff_home { setup_steps }  # jac:ignore[W2037] authenticated endpoint
import from ..shell.AppLink { AppLink }
import from .nav { section_path, section_label }

glob HIDDEN_EVENT: str = "africinemas-setup-guide",
     POLL_MS: int = 15000,
     # What to do at each step, in a line (the keys of core/reporting/staff_home.jac).
     HINTS: dict[str, str] = {
         "venue": "Add the place where your screens are: its name, address and opening details.",
         "screen": "Add a screen at your venue, draw its seats, then publish the layout.",
         "prices": "Set what each ticket type costs, and any seat-zone prices.",
         "movie": "Add a movie you'll show, with its poster and details.",
         "showtime": "Schedule the movie on a screen and publish the showtime so customers can book it.",
         "branding": "Upload your logo, let the AI design your storefront, then publish it.",
         "team": "Invite the people who sell and check tickets.",
         "verify": "Your details and your business's documents, for AfriCinemas to check before you go live. The cinema's owner does this."
     };

def _key(slug: str) -> str {
    return f"africinemas:setup-guide-hidden:{slug}";
}

def:pub guide_hidden(slug: str) -> bool {
    win: any = window;  # jac:ignore[W1037,W2001]
    try {
        return win.localStorage.getItem(_key(slug)) == "1";
    } except Exception {
        return False;
    }
}

def:pub hide_guide(slug: str, hidden: bool) {
    # Hides (or brings back) the guide for this cinema and tells every use_guide_hidden.
    win: any = window;  # jac:ignore[W1037,W2001]
    try {
        if hidden {
            win.localStorage.setItem(_key(slug), "1");
        } else {
            win.localStorage.removeItem(_key(slug));
        }
    } except Exception {
        console.warn("hiding the setup guide can't be remembered here");
    }
    event_class: any = win.CustomEvent;  # jac:ignore[W1037]
    win.dispatchEvent(
        new(event_class, HIDDEN_EVENT, {"detail": {"slug": slug, "hidden": hidden}})
    );
}

def:pub use_guide_hidden(slug: str) -> bool {
    [hidden, set_hidden] = useState(guide_hidden(slug));

    def listen -> any {  # jac:ignore[W1037]
        win: any = window;  # jac:ignore[W1037,W2001]
        set_hidden(guide_hidden(slug));
        heard = lambda (e: any) { if e.detail.slug == slug {  # jac:ignore[W1037]
            set_hidden(e.detail.hidden);
        }};  # jac:ignore[W1037]
        win.addEventListener(HIDDEN_EVENT, heard);
        return lambda { win.removeEventListener(HIDDEN_EVENT, heard); };
    }
    useEffect(listen, [slug]);
    return hidden;
}

def:pub SetupGuide(slug: str, section: str, page: str) -> JsxElement {
    # `section` is the page's section key; `page` changes on every page change.
    [steps, set_steps] = useState(None);
    hidden = use_guide_hidden(slug);

    async def load {
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await setup_steps(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("setup steps failed", e);
            return;
        }
        set_steps(got if got["ok"] else None);
    }

    def keep_up -> any {  # jac:ignore[W1037]
        load();
        win: any = window;  # jac:ignore[W1037,W2001]
        timer = win.setInterval(lambda { load(); }, POLL_MS);  # jac:ignore[W6001] client-only code
        return lambda { win.clearInterval(timer); };  # jac:ignore[W6001] client-only code
    }
    useEffect(keep_up, [slug, page]);

    found: dict[str, any] | None = steps;  # jac:ignore[W1037]
    if hidden or found is None or not found["next"] {
        return <span hidden={True}/>;
    }
    listed: list[dict[str, any]] = found["steps"];  # jac:ignore[W1037]
    total = len(listed);
    at = 0;
    for (i, s) in enumerate(listed) {
        if s["key"] == found["next"] {
            at = i;
        }
    }
    step: dict[str, any] = listed[at];  # jac:ignore[W1037]
    done = int(found["done"]);
    here = section == step["section"];
    where = section_label(step["section"]);
    return
        <section
            aria-labelledby="setup-guide-title"
            data-testid="setup-guide"
            data-step={step["key"]}
            className="flex flex-col gap-3 rounded-xl bg-card p-4 ring-1 ring-primary/30"
        >
            <div className="flex items-center justify-between gap-3">
                <p
                    className="text-xs font-medium tracking-wide text-muted-foreground uppercase"
                    data-testid="setup-guide-progress"
                >
                    Set up your cinema · Step {at + 1} of {total}
                </p>
                <Button
                    variant="ghost"
                    className="min-h-11 text-sm"
                    data-testid="hide-setup-guide"
                    onClick={lambda { hide_guide(slug, True); }}
                >
                    Hide the guide
                </Button>
            </div>
            <span
                aria-hidden="true"
                className="h-1.5 overflow-hidden rounded-full bg-muted"
            >
                <span
                    className="block h-full rounded-full bg-primary"
                    style={{"width": f"{done * 100 / total}%"}}
                />
            </span>
            <div
                className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"
            >
                <div className="flex flex-col gap-1">
                    <h2 id="setup-guide-title" className="font-semibold">
                        {step["label"]}
                    </h2>
                    <p className="text-sm text-muted-foreground">
                        {HINTS[step["key"]]}
                    </p>
                </div>
                {here
                    and <p
                        className="text-sm font-medium"
                        data-testid="setup-guide-here"
                    >
                        You're in the right place.
                    </p>}
                {not here
                    and <Button asChild={True} className="min-h-11 shrink-0">
                        <AppLink
                            to={section_path(slug, step["section"])}
                            testid="guide-go"
                        >
                            Go to {where}
                        </AppLink>
                    </Button>}
            </div>
        </section>;
}
