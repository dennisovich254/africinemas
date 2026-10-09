"""`/`: the AfriCinemas landing page (P3.9).

One bold moment, then calm (ui-ux-pro-max "Funnel", motion 3/10): a hero over a muted,
looping video of an empty cinema hall, then what a cinema gets (six features, the value
first), then three steps, each beside a small example of
the product (a screen's programme, the M-Pesa prompt, a QR ticket), then one closing
call. The hero and the examples always wear the storefront's dark tokens (a `.dark`
wrapper, styles/landing.css); the rest follows the device. The video stays still with
"reduce motion" or data saver, and has a pause button (WCAG 2.2.2). Signed-in staff get
"Your cinemas" instead of "Sign in". The words come from landing_content.jac; the theme
tests read the primary-cta, secondary-cta and wordmark test ids.
"""

import from react { useState, useEffect, useRef }
import from "@jac/runtime" { jacIsLoggedIn }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" {
    PauseIcon,
    PlayIcon,
    SeatSelectorIcon,
    PaintBoardIcon,
    SmartPhone01Icon,
    QrCode01Icon,
    ChartColumnIcon,
    AiChat02Icon
}
import from ...components.ui.button { Button }
import from ..theme.ThemeProvider { ThemeProvider }
import from ..shell.AppLink { AppLink }
import from .landing_content {
    HERO,
    FEATURES_HEAD,
    FEATURES,
    STEPS_HEAD,
    STEPS,
    PROGRAMME,
    MPESA,
    TICKET,
    CLOSING,
    AUDIENCE,
    FOOTER
}

glob WIDTH: str = "mx-auto w-full max-w-6xl px-4 sm:px-6",
     QR_SIZE: int = 21,
     FEATURE_ICONS: dict[str, any] = {  # jac:ignore[W1037]
         "seat": SeatSelectorIcon,
         "brand": PaintBoardIcon,
         "mpesa": SmartPhone01Icon,
         "door": QrCode01Icon,
         "counter": ChartColumnIcon,
         "ai": AiChat02Icon
     };

def in_finder(x: int, y: int) -> bool {
    # The three corner squares of a QR code: a ring, a gap, and a solid centre.
    for (fx, fy) in [(0, 0), (QR_SIZE - 7, 0), (0, QR_SIZE - 7)] {
        dx = x - fx;
        dy = y - fy;
        if 0 <= dx and dx < 7 and 0 <= dy and dy < 7 {
            ring = dx == 0 or dx == 6 or dy == 0 or dy == 6;
            centre = 2 <= dx and dx <= 4 and 2 <= dy and dy <= 4;
            return ring or centre;
        }
    }
    return False;
}

def near_finder(x: int, y: int) -> bool {
    return (x < 8 and y < 8)
        or (x > QR_SIZE - 9 and y < 8)
        or (x < 8 and y > QR_SIZE - 9);
}

def:pub qr_grid -> list[bool] {
    # A QR-like pattern for the example ticket, row by row: the finder squares and a
    # fixed pseudo-random fill. Purely an illustration; it encodes nothing.
    cells: list[bool] = [];
    seed = 2468;
    for y in range(QR_SIZE) {
        for x in range(QR_SIZE) {
            seed = (seed * 1103 + 12345) % 65536;
            if near_finder(x, y) {
                cells.append(in_finder(x, y));
            } else {
                cells.append(seed % 100 > 52);
            }
        }
    }
    return cells;
}

def HallVideo -> JsxElement {
    # The cinema hall behind the hero: muted and looping unless the visitor asked for
    # less motion or less data, with a button to pause it.
    video = useRef(None);
    [playing, set_playing] = useState(False);

    async def start {
        win: any = window;  # jac:ignore[W1037,W2001]
        nav: any = win.navigator;  # jac:ignore[W1037]
        still = win.matchMedia("(prefers-reduced-motion: reduce)").matches
            or (nav.connection and nav.connection.saveData);
        player: any = video.current;  # jac:ignore[W1037]
        if still or not player {
            return;
        }
        try {
            await player.play();
            set_playing(True);
        } except Exception as e {
            console.warn("the hero video didn't start", e);
        }
    }

    def begin {
        start();
    }
    useEffect(begin, []);

    def toggle {
        player: any = video.current;  # jac:ignore[W1037]
        if not player {
            return;
        }
        if player.paused {
            player.play();
            set_playing(True);
        } else {
            player.pause();
            set_playing(False);
        }
    }

    return
        <div>
            <div className="landing-hall" aria-hidden="true">
                <video
                    ref={video}
                    data-testid="hall-video"
                    muted={True}
                    loop={True}
                    playsInline={True}
                    preload="metadata"
                    poster={HERO["video"] + ".jpg"}
                >
                    <source src={HERO["video"] + ".webm"} type="video/webm"/>
                    <source src={HERO["video"] + ".mp4"} type="video/mp4"/>
                </video>
            </div>
            <button
                type="button"
                data-testid="hall-pause"
                aria-pressed={"false" if playing else "true"}
                aria-label={HERO["pause"] if playing else HERO["play"]}
                onClick={toggle}
                className="absolute right-4 bottom-6 z-10 grid size-11 cursor-pointer place-items-center rounded-full border border-foreground/35 bg-background/60 text-foreground transition-colors hover:border-foreground sm:right-6"
            >
                <HugeiconsIcon
                    icon={PauseIcon if playing else PlayIcon}
                    strokeWidth={2}
                    aria-hidden="true"
                    className="size-4"
                />
            </button>
        </div>;
}

def Proof(kind: str) -> JsxElement {
    # A small example of the product beside each step, always in the dark storefront look.
    body: any = None;  # jac:ignore[W1037]
    if kind == "programme" {
        body = <div className="flex flex-col">
            <span
                className="text-xs font-semibold tracking-[0.14em] text-primary uppercase"
            >
                Screen 1 · Friday
            </span>
            {[
                <div
                    key={p["title"]}
                    className="flex items-center justify-between gap-3 border-b py-3 last:border-b-0"
                >
                    <span className="flex flex-col">
                        {p["title"]}
                        <span className="text-sm text-muted-foreground">
                            {p["time"]}
                        </span>
                    </span>
                    <span
                        className={"rounded-full px-2.5 py-1 text-xs font-semibold "
                            + (
                                "bg-primary text-primary-foreground"
                                    if p["state"] == "On sale"
                                    else "border text-muted-foreground"
                            )}
                    >
                        {p["state"]}
                    </span>
                </div> for p in PROGRAMME
            ]}
        </div>;
    } elif kind == "mpesa" {
        body = <div className="flex flex-col gap-3">
            <span
                className="text-xs font-semibold tracking-[0.14em] text-primary uppercase"
            >
                {MPESA["caption"]}
            </span>
            <div className="rounded-xl bg-foreground p-4 text-background">
                <p className="font-semibold leading-snug">{MPESA["prompt"]}</p>
                <p
                    className="mt-3 border-b border-background/30 pb-2 text-center text-lg tracking-[0.4em]"
                    aria-hidden="true"
                >
                    ••••
                </p>
                <p className="mt-2 text-sm opacity-75">{MPESA["pin"]}</p>
            </div>
        </div>;
    } else {
        body = <div className="flex flex-col gap-3">
            <span
                className="text-xs font-semibold tracking-[0.14em] text-primary uppercase"
            >
                Ticket
            </span>
            <div
                className="grid grid-cols-[1fr_auto] items-center gap-4 rounded-xl bg-foreground p-4 text-background"
            >
                <span className="flex flex-col">
                    <span className="font-display text-2xl leading-none">
                        {TICKET["film"]}
                    </span>
                    <span className="mt-1 text-sm opacity-75">{TICKET["when"]}</span>
                    <span className="text-sm opacity-75">{TICKET["where"]}</span>
                </span>
                <span
                    aria-hidden="true"
                    className="grid size-20 grid-cols-[repeat(21,1fr)]"
                >
                    {[
                        <span key={i} className={"bg-current" if on else ""}></span>
                        for (i, on) in enumerate(qr_grid())
                    ]}
                </span>
            </div>
        </div>;
    }
    return
        <div className="dark">
            <div
                data-surface="storefront"
                className="w-full max-w-sm justify-self-center rounded-2xl p-6 text-sm"
            >
                {body}
            </div>
        </div>;
}

def:pub LandingPage -> JsxElement {
    signed_in = jacIsLoggedIn();
    account = (
        <AppLink
            to="/app"
            className="inline-flex min-h-11 items-center rounded-md border px-4 text-sm font-medium transition-colors hover:border-foreground"
        >
            {HERO["signed_in"]}
        </AppLink>
            if signed_in
            else <AppLink
                to="/login"
                className="inline-flex min-h-11 items-center rounded-md border px-4 text-sm font-medium transition-colors hover:border-foreground"
            >
                {HERO["sign_in"]}
            </AppLink>
    );
    return
        <ThemeProvider surface="storefront">
            <div data-testid="landing" className="flex min-h-svh flex-col">
                <div className="dark">
                    <header data-surface="storefront" className="landing-hero">
                        <HallVideo/>
                        <div className={WIDTH}>
                            <nav
                                aria-label="Main"
                                className="flex h-18 items-center justify-between gap-4"
                            >
                                <span
                                    data-testid="wordmark"
                                    className="font-display text-3xl leading-none"
                                >
                                    AfriCinemas
                                </span>
                                {account}
                            </nav>
                            <div
                                className="landing-rise flex min-h-[clamp(520px,74svh,760px)] max-w-2xl flex-col justify-center gap-6 pt-6 pb-24"
                            >
                                <p
                                    className="text-sm font-semibold tracking-[0.14em] text-primary uppercase"
                                >
                                    {HERO["eyebrow"]}
                                </p>
                                <h1
                                    className="font-display text-6xl leading-[0.9] text-balance sm:text-7xl lg:text-8xl"
                                >
                                    {HERO["title"]}
                                </h1>
                                <p className="max-w-[34ch] text-lg text-foreground/85">
                                    {HERO["lead"]}
                                </p>
                                <div className="flex flex-wrap gap-3">
                                    <Button
                                        asChild={True}
                                        className="min-h-12 px-6 text-base"
                                    >
                                        <AppLink to="/signup" testid="primary-cta">
                                            {HERO["cta"]}
                                        </AppLink>
                                    </Button>
                                    <Button
                                        asChild={True}
                                        variant="outline"
                                        className="min-h-12 px-6 text-base"
                                    >
                                        <a href="#how" data-testid="secondary-cta">
                                            {HERO["more"]}
                                        </a>
                                    </Button>
                                </div>
                            </div>
                        </div>
                    </header>
                </div>
                <main className="flex flex-1 flex-col">
                    <section
                        aria-labelledby="features-heading"
                        className={WIDTH + " pt-20 sm:pt-28"}
                    >
                        <div className="max-w-2xl">
                            <h2
                                id="features-heading"
                                className="font-display text-5xl leading-[0.95] text-balance sm:text-6xl"
                            >
                                {FEATURES_HEAD["title"]}
                            </h2>
                            <p className="mt-3 text-muted-foreground">
                                {FEATURES_HEAD["text"]}
                            </p>
                        </div>
                        <ul
                            data-testid="features"
                            className="mt-10 grid gap-4 sm:grid-cols-2 lg:grid-cols-3"
                        >
                            {[
                                <li
                                    key={f["title"]}
                                    className="flex flex-col gap-3 rounded-2xl border p-6"
                                >
                                    <HugeiconsIcon
                                        icon={FEATURE_ICONS[f["icon"]]}
                                        strokeWidth={1.8}
                                        aria-hidden="true"
                                        className="size-6 text-[var(--ac-accent-ink)]"
                                    />
                                    <h3 className="text-lg font-semibold leading-snug">
                                        {f["title"]}
                                    </h3>
                                    <p className="text-muted-foreground">{f["text"]}</p>
                                </li> for f in FEATURES
                            ]}
                        </ul>
                    </section>
                    <section
                        id="how"
                        aria-labelledby="how-heading"
                        className={WIDTH + " pt-20 pb-10 sm:pt-28"}
                    >
                        <div className="max-w-2xl">
                            <h2
                                id="how-heading"
                                className="font-display text-5xl leading-[0.95] text-balance sm:text-6xl"
                            >
                                {STEPS_HEAD["title"]}
                            </h2>
                            <p className="mt-3 text-muted-foreground">
                                {STEPS_HEAD["text"]}
                            </p>
                        </div>
                        <ol data-testid="how-it-works" className="mt-12">
                            {[
                                <li
                                    key={s["title"]}
                                    className="grid items-center gap-8 border-t py-10 md:grid-cols-2 md:gap-14"
                                >
                                    <div
                                        className={"flex flex-col gap-3"
                                            + (" md:order-2" if i % 2 == 1 else "")}
                                    >
                                        <span
                                            className="font-display text-2xl tracking-wider text-[var(--ac-accent-ink)]"
                                        >
                                            {"0" + str(i + 1)}
                                        </span>
                                        <h3
                                            className="font-display text-4xl leading-[0.95] sm:text-5xl"
                                        >
                                            {s["title"]}
                                        </h3>
                                        <p
                                            className="max-w-[44ch] text-muted-foreground"
                                        >
                                            {s["text"]}
                                        </p>
                                    </div>
                                    {Proof(s["proof"])}
                                </li> for (i, s) in enumerate(STEPS)
                            ]}
                        </ol>
                    </section>
                    <section
                        aria-labelledby="closing-heading"
                        className={WIDTH + " pb-20"}
                    >
                        <div className="dark">
                            <div
                                data-surface="storefront"
                                className="grid gap-6 rounded-3xl p-7 sm:p-12 md:grid-cols-[1fr_auto] md:items-center"
                            >
                                <div className="flex flex-col gap-3">
                                    <h2
                                        id="closing-heading"
                                        className="font-display text-5xl leading-[0.95]"
                                    >
                                        {CLOSING["title"]}
                                    </h2>
                                    <p className="text-muted-foreground">
                                        {CLOSING["text"]}
                                    </p>
                                    <ul
                                        data-testid="audience"
                                        aria-label="Who it's for"
                                        className="flex flex-wrap gap-x-6 gap-y-1 text-sm text-muted-foreground"
                                    >
                                        {[
                                            <li key={a[0]}>
                                                <span
                                                    className="font-semibold text-foreground"
                                                >
                                                    {a[0]}
                                                </span>
                                                {" · "}
                                                {a[1]}
                                            </li> for a in AUDIENCE
                                        ]}
                                    </ul>
                                </div>
                                <Button
                                    asChild={True}
                                    className="min-h-12 px-6 text-base"
                                >
                                    <AppLink to="/signup">{CLOSING["cta"]}</AppLink>
                                </Button>
                            </div>
                        </div>
                    </section>
                </main>
                <footer className="border-t">
                    <p className={WIDTH + " py-6 text-sm text-muted-foreground"}>
                        {FOOTER}
                    </p>
                </footer>
            </div>
        </ThemeProvider>;
}
