"""Scanner: checking tickets at the door (P6.4, architecture §48; ADR-0024).

Staff who may scan tickets pick the showtime they're checking (the showtimes whose door
is open now, at their venues: door_showtimes), then scan each ticket's QR code with the
camera or type its reference. Every code goes to redeem_ticket (6.2), and the result
shows large: Admit, with the seat, or the reason it's refused, in words, with an icon as
well as a color. A code the camera just read isn't sent again for a few seconds, so a
ticket held in front of it counts once; a typed reference is always checked.

The camera starts only when asked (it needs permission) and stops when the page or the
showtime changes. It reads codes through a decoder: qr-scanner, unless the page was
given another one as window.__africinemasDecoder, which is how the browser tests scan
without a camera. A decoder has available() -> Promise<bool> and
start(video, on_code) -> Promise<stop function>. With no camera, typing the reference
still works.
"""

import from react { useState, useEffect }
import from "qr-scanner" { default as QrScanner }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" {
    CheckmarkCircle02Icon,
    CancelCircleIcon,
    Camera01Icon
}
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.booking.redeem_api { door_showtimes, redeem_ticket }  # jac:ignore[W2037] def:priv endpoints over the server pin (JI-027)
import from ..storefront.showtimes { time_label, long_day_label }

glob REPEAT_MS: int = 4000;

def _scanner_class -> any {  # jac:ignore[W1037]
    # The QrScanner class as `any`: through a default import, the checker loses its
    # static methods such as hasCamera (docs/jac-issues/JI-041).
    found: any = QrScanner;  # jac:ignore[W1037]
    return found;
}

async def _real_start(video: any, on_code: any) -> any {  # jac:ignore[W1037]
    scanner: any = new(  # jac:ignore[W1037,W2001,W1051]
        _scanner_class(),
        video,
        lambda (r: any) { on_code(r.data); },  # jac:ignore[W1037]
        {
            "returnDetailedScanResult": True,
            "preferredCamera": "environment",
            "highlightScanRegion": True
        }
    );
    await scanner.start();
    return lambda {
        scanner.stop();
        scanner.destroy();
    };
}

def _decoder -> any {  # jac:ignore[W1037]
    # The test decoder if the page was given one, else the camera through qr-scanner.
    win: any = window;  # jac:ignore[W1037,W2001]
    if win.__africinemasDecoder {
        return win.__africinemasDecoder;
    }
    return {
        "available": lambda -> any { return _scanner_class().hasCamera(); },  # jac:ignore[W1037]
        "start": _real_start
    };
}

def:pub describe(answer: dict[str, any], tz: str) -> dict[str, str] {  # jac:ignore[W1037]
    # What the result card says: {"kind": "admit" | "refuse", "title", "detail"}.
    if answer["ok"] {
        t: dict[str, str] = answer["ticket"];
        return {
            "kind": "admit",
            "title": "Admit",
            "detail": f"Seat {t['seat_label']} · {t['ticket_name']}"
        };
    }
    e: dict[str, any] = answer["error"];  # jac:ignore[W1037]
    code: str = e["code"];
    title = "Not admitted";
    detail: str = e["message"];
    if code == "already_redeemed" {
        title = "Already used";
        detail = f"Scanned at {time_label(e['used_at'], tz)} by {e['used_by']}.";
    } elif code == "wrong_showtime" {
        title = "Wrong showtime";
        detail = f"This ticket is for {e['movie_title']}, {long_day_label(
            e['starts_at'], tz
        )} at {time_label(e['starts_at'], tz)}.";
    } elif code == "too_early" {
        title = "Too early";
        detail = f"Doors open at {time_label(e['opens_at'], tz)}.";
    } elif code == "showtime_over" {
        title = "Showtime over";
    } elif code == "ticket_voided" {
        title = "Cancelled ticket";
    } elif code == "ticket_refunded" {
        title = "Refunded ticket";
    } elif code == "invalid_code" {
        title = "Not a ticket";
    } elif code == "unknown_ticket" {
        title = "Unknown ticket";
    }
    return {"kind": "refuse", "title": title, "detail": detail};
}

def ResultCard(result: dict[str, str]) -> JsxElement {
    admit: bool = result["kind"] == "admit";
    return
        <div
            data-testid="scan-result"
            data-kind={result["kind"]}
            data-at={result["at"]}
            className={"flex items-center gap-4 rounded-lg border-2 p-4 "
                + (
                    "border-green-700 bg-green-50 text-green-950 dark:border-green-500 dark:bg-green-950 dark:text-green-50"
                        if admit
                        else "border-destructive bg-destructive/10 text-foreground"
                )}
        >
            <HugeiconsIcon
                icon={CheckmarkCircle02Icon if admit else CancelCircleIcon}
                aria-hidden="true"
                className="size-10 shrink-0"
            />
            <div className="flex flex-col gap-0.5">
                <p data-testid="scan-title" className="text-2xl font-semibold">
                    {result["title"]}
                </p>
                <p data-testid="scan-detail" className="text-base">
                    {result["detail"]}
                </p>
            </div>
        </div>;
}

def:pub ShowtimeChoice(
    showtime: dict[str, str],
    tz: str,
    chosen: bool,
    on_choose: any,  # jac:ignore[W1037]
    with_day: bool = False,
    testid: str = "door-showtime"
) -> JsxElement {
    # One showtime to choose: its time (and day, for the box office, P6.5), movie and
    # place.
    when: str = time_label(showtime["starts_at"], tz);
    if with_day {
        when = f"{long_day_label(showtime['starts_at'], tz)}, {when}";
    }
    return
        <button
            type="button"
            data-testid={testid}
            aria-pressed={"true" if chosen else "false"}
            onClick={lambda { on_choose(showtime["screening_id"]); }}
            className={"flex min-h-11 flex-col items-start rounded-md border px-3 py-2 text-left "
                + ("border-primary bg-primary/10" if chosen else "hover:bg-muted")}
        >
            <span className="font-medium">{f"{when} · {showtime['movie_title']}"}</span>
            <span className="text-sm text-muted-foreground">
                {" · ".join(
                    [
                        p
                        for p in [showtime["venue"], showtime["screen"]]
                        if p
                    ]
                )}
            </span>
        </button>;
}

def Camera(on_code: any, screening_id: str) -> JsxElement {  # jac:ignore[W1037]
    # The camera view; starts when asked, stops when the showtime or page changes.
    has video: Ref[any] = Ref();  # jac:ignore[W1037]
    [state, set_state] = useState("off");
    camera: str = state;

    def stop_on_change -> any {  # jac:ignore[W1037]
        set_state("off");
        return lambda {};
    }
    useEffect(stop_on_change, [screening_id]);

    def run -> any {  # jac:ignore[W1037]
        if camera != "starting" {
            return lambda {};
        }
        stopper: any = None;  # jac:ignore[W1037]
        cancelled: list[bool] = [False];

        async def begin {
            decoder: any = _decoder();  # jac:ignore[W1037]
            try {
                ok: bool = await decoder.available();
                if not ok {
                    set_state("unavailable");
                    return;
                }
                stop_fn: any = await decoder.start(video.current, on_code);  # jac:ignore[W1037]
                if cancelled[0] {
                    stop_fn();
                    return;
                }
                stopper = stop_fn;
                set_state("on");
            } except Exception as e {
                console.warn("camera failed", e);
                set_state("unavailable");
            }
        }
        begin();
        return lambda {
            cancelled[0] = True;
            if stopper {
                stopper();
            }
        };
    }
    useEffect(run, [camera == "starting" or camera == "on", screening_id]);

    return
        <div className="flex flex-col gap-2">
            <div
                className={"overflow-hidden rounded-lg border bg-black "
                    + ("" if camera == "on" or camera == "starting" else "hidden")}
            >
                <video
                    ref={video}
                    data-testid="camera-view"
                    muted={True}
                    playsInline={True}
                    className="aspect-square w-full object-cover sm:aspect-video"
                />
            </div>
            {camera == "unavailable"
                and <p
                    data-testid="camera-unavailable"
                    className="text-sm text-muted-foreground"
                >
                    The camera isn't available (no camera, or permission was refused). Type the ticket reference instead.
                </p>}
            {(
                <Button
                    variant="outline"
                    data-testid="stop-camera"
                    onClick={lambda { set_state("off"); }}
                    className="min-h-11 w-fit"
                >
                    Stop camera
                </Button>
            )
                if camera == "on" or camera == "starting"
                else <Button
                    data-testid="start-camera"
                    onClick={lambda { set_state("starting"); }}
                    className="min-h-11 w-fit"
                >
                    <HugeiconsIcon icon={Camera01Icon} aria-hidden="true"/>
                    Start camera
                </Button>}
        </div>;
}

def:pub ScannerSection(slug: str) -> JsxElement {
    [door, set_door] = useState(None);
    [chosen, set_chosen] = useState("");
    [result, set_result] = useState(None);
    [busy, set_busy] = useState(False);
    [typed, set_typed] = useState("");
    has last: Ref[any] = Ref({"code": "", "at": 0});  # jac:ignore[W1037]
    found: dict[str, any] | None = door;  # jac:ignore[W1037]
    screening_id: str = chosen;
    shown: dict[str, str] | None = result;

    async def load {
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await door_showtimes(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("door showtimes failed", e);
            got = {
                "ok": False,
                "error": {"message": "We couldn't load the showtimes."}
            };
        }
        set_door(got);
        if got["ok"] and len(got["showtimes"]) == 1 {
            set_chosen(got["showtimes"][0]["screening_id"]);
        }
    }

    def start_loading -> any {  # jac:ignore[W1037]
        load();
        return lambda {};
    }
    useEffect(start_loading, [slug]);

    async def check(code: str, from_camera: bool) {
        text = code.strip();
        if not text or not screening_id {
            return;
        }
        now_ms: float = Date.now();  # jac:ignore[W2001]
        seen: any = last.current;  # jac:ignore[W1037]
        seen_at: float = seen["at"];
        # A ticket held in front of the camera is read many times: it counts once.
        if from_camera and seen["code"] == text and now_ms - seen_at < REPEAT_MS {
            return;
        }
        last.current = {"code": text, "at": now_ms};
        set_busy(True);
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await redeem_ticket(slug, screening_id, text);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("redeem failed", e);
            answer = {
                "ok": False,
                "error": {
                    "code": "",
                    "message": "We couldn't reach the server. Try again."
                }
            };
        }
        set_busy(False);
        described = describe(answer, found["timezone"] if found is not None else "UTC");
        # A stamp per result, so the same answer twice still reads as a new one.
        described["at"] = str(now_ms);
        set_result(described);
        win: any = window;  # jac:ignore[W1037,W2001]
        if win.navigator.vibrate {
            win.navigator.vibrate(80 if described["kind"] == "admit" else [60, 40, 60]);
        }
    }

    def typed_changed(e: any) {  # jac:ignore[W1037]
        set_typed(e.target.value);
    }

    def submit(e: any) {  # jac:ignore[W1037]
        e.preventDefault();
        check(typed, False);
        set_typed("");
    }

    if found is None {
        return <Spinner aria-label="Loading"/>;
    }
    if not found["ok"] {
        return
            <p role="alert" data-testid="scanner-problem" className="text-destructive">
                {found["error"]["message"]}
            </p>;
    }
    showtimes: list[dict[str, str]] = found["showtimes"];
    tz: str = found["timezone"];
    if len(showtimes) == 0 {
        return
            <div
                data-testid="no-open-doors"
                className="flex flex-col items-start gap-3"
            >
                <p className="text-muted-foreground">
                    No doors are open right now. A showtime appears here from two hours before it starts until it ends.
                </p>
                <Button
                    variant="outline"
                    onClick={lambda { load(); }}
                    className="min-h-11"
                >
                    Check again
                </Button>
            </div>;
    }
    return
        <div data-testid="scanner" className="flex max-w-xl flex-col gap-6">
            <fieldset className="flex flex-col gap-2">
                <legend className="mb-2 font-medium">Showtime you're checking</legend>
                {[
                    <ShowtimeChoice
                        key={s["screening_id"]}
                        showtime={s}
                        tz={tz}
                        chosen={s["screening_id"] == screening_id}
                        on_choose={lambda (sid: str) {
                            set_chosen(sid);
                            set_result(None);
                        }}
                    /> for s in showtimes
                ]}
            </fieldset>
            {len(screening_id) > 0
                and <div className="flex flex-col gap-6">
                    <div role="status" aria-live="polite" className="min-h-24">
                        {shown is not None and <ResultCard result={shown}/>}{busy
                            and shown is None
                            and <Spinner aria-label="Checking"/>}
                    </div>
                    <Camera
                        on_code={lambda (code: str) { check(code, True); }}
                        screening_id={screening_id}
                    />
                    <form
                        onSubmit={submit}
                        noValidate={True}
                        className="flex flex-col gap-2"
                    >
                        <Label htmlFor="ticket-reference">Ticket reference</Label>
                        <div className="flex flex-col gap-2 sm:flex-row">
                            <Input
                                id="ticket-reference"
                                name="reference"
                                autoComplete="off"
                                autoCapitalize="characters"
                                spellCheck={False}
                                placeholder="7K2M 9QXR 4HJN P3WD"
                                value={typed}
                                onChange={typed_changed}
                                className="h-11 font-mono text-base sm:max-w-xs"
                            />
                            <Button
                                type="submit"
                                data-testid="check-ticket"
                                disabled={busy}
                                className="min-h-11"
                            >
                                Check ticket
                            </Button>
                        </div>
                    </form>
                </div>}
        </div>;
}
