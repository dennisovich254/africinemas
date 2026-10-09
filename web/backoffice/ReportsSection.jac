"""`/app/:slug/reports`: the owner's dashboard (P7.3, on P7.1's sales report; ADR-0026).

Filters in one row (a period preset or custom dates, and a venue), then two blocks that
count on different days, so each says which: "Money taken" (the day the money came in)
and "Showtimes in this period" (the day the showtime starts). Money taken has its tiles
and the takings chart; showtimes have theirs, the top movies and the drill-down. For
staff with financial_reports.read; the server checks it on every request.
"""

import from react { useState, useEffect }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.reporting.report_api { sales_report }  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)
import from .report_view { PRESETS, preset_range, period_label, percent, money_label }
import from .report_parts { KpiTile, TakingsChart, TopMovies, DrillDown }

glob SELECT_CLASSES: str = "min-h-11 w-full rounded-md border border-input bg-background px-3 text-sm sm:w-auto";

def PresetButton(preset: str, label: str, chosen: str, on_pick: any) -> JsxElement {  # jac:ignore[W1037]
    return
        <Button
            type="button"
            size="sm"
            variant={"default" if preset == chosen else "outline"}
            aria-pressed={preset == chosen}
            data-testid={f"preset-{preset}"}
            className="min-h-11"
            onClick={lambda { on_pick(preset); }}
        >
            {label}
        </Button>;
}

def:pub ReportsSection(slug: str, shift_open: bool = True) -> JsxElement {
    [today, set_today] = useState("");
    [preset, set_preset] = useState("today");
    [first, set_first] = useState("");
    [last, set_last] = useState("");
    [venue, set_venue] = useState("");
    [venues, set_venues] = useState([]);
    [answer, set_answer] = useState(None);
    [failed, set_failed] = useState("");
    [loading, set_loading] = useState(True);

    async def load(date_from: str, date_to: str, venue_id: str) {
        got: any = None;  # jac:ignore[W1037]
        set_loading(True);
        try {
            got = await sales_report(slug, date_from, date_to, venue_id);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("sales_report failed", e);
            set_loading(False);
            set_failed("We couldn't load the report. Refresh the page to try again.");
            return;
        }
        set_loading(False);
        if not got["ok"] {
            set_failed(got["error"]["message"]);
            return;
        }
        set_failed("");
        set_today(got["today"]);
        set_answer(got);
        if not venue_id {
            # The venue filter lists every venue seen in a whole-cinema report.
            known: list[dict[str, str]] = venues;
            seen: list[str] = [v["venue_id"] for v in known];
            added: list[dict[str, str]] = [];
            for v in got["report"]["venues"] {
                if v["venue_id"] not in seen {
                    added.append({"venue_id": v["venue_id"], "name": v["name"]});
                }
            }
            if len(added) > 0 {
                set_venues(known + added);
            }
        }
    }

    # The first request asks for "today" without dates: the server answers with the
    # cinema's day, from which the other presets count.
    def start_loading {
        load("", "", venue);
    }
    useEffect(start_loading, [slug, shift_open]);

    def pick(key: str) {
        set_preset(key);
        if key == "custom" {
            set_first(first or today);
            set_last(last or today);
            return;
        }
        span = preset_range(key, today);
        load(span[0], span[1], venue);
    }

    def type_first(e: any) {  # jac:ignore[W1037]
        set_first(e.target.value);
    }

    def type_last(e: any) {  # jac:ignore[W1037]
        set_last(e.target.value);
    }

    def show_custom {
        load(first, last, venue);
    }

    def pick_venue(e: any) {  # jac:ignore[W1037]
        chosen: str = e.target.value;
        set_venue(chosen);
        span = [first, last] if preset == "custom" else preset_range(preset, today);
        load(span[0], span[1], chosen);
    }

    if failed and answer is None {
        return
            <Alert variant="destructive">
                <AlertDescription>{failed}</AlertDescription>
            </Alert>;
    }
    if answer is None {
        return
            <p role="status" className="flex items-center gap-2 text-muted-foreground">
                <Spinner aria-hidden="true"/>
                Loading the report…
            </p>;
    }
    got: dict[str, any] = answer;  # jac:ignore[W1037]
    sales: dict[str, any] = got["report"];  # jac:ignore[W1037]
    currency: str = got["currency"];
    takings: dict[str, int] = sales["takings"];
    shown: dict[str, any] = sales["attendance"];  # jac:ignore[W1037]
    full: float = shown["occupancy_pct"];
    places: list[dict[str, str]] = venues;
    span_text = period_label(sales["first"], sales["last"]);
    return
        <div className="flex flex-col gap-8">
            <div className="flex flex-col gap-3">
                <div role="group" aria-label="Period" className="flex flex-wrap gap-2">
                    {[
                        <PresetButton
                            key={k}
                            preset={k}
                            label={label}
                            chosen={preset}
                            on_pick={pick}
                        /> for (k, label) in PRESETS
                    ]}
                </div>
                {preset == "custom"
                    and <div className="flex flex-wrap items-end gap-3">
                        <div className="flex flex-col gap-1">
                            <Label htmlFor="report-from">From</Label>
                            <Input
                                id="report-from"
                                type="date"
                                value={first}
                                onChange={type_first}
                            />
                        </div>
                        <div className="flex flex-col gap-1">
                            <Label htmlFor="report-to">To</Label>
                            <Input
                                id="report-to"
                                type="date"
                                value={last}
                                onChange={type_last}
                            />
                        </div>
                        <Button
                            type="button"
                            className="min-h-11"
                            data-testid="custom-show"
                            onClick={show_custom}
                        >
                            Show
                        </Button>
                    </div>}
                <div
                    className="flex flex-col gap-1 sm:flex-row sm:items-center sm:gap-3"
                >
                    <Label htmlFor="report-venue">Venue</Label>
                    <select
                        id="report-venue"
                        className={SELECT_CLASSES}
                        value={venue}
                        onChange={pick_venue}
                    >
                        <option value="">All venues</option>
                        {[
                            <option key={v["venue_id"]} value={v["venue_id"]}>
                                {v["name"]}
                            </option> for v in places
                        ]}
                    </select>
                </div>
                <p
                    role="status"
                    data-testid="report-period"
                    className="flex items-center gap-2 text-sm text-muted-foreground"
                >
                    {loading and <Spinner aria-hidden="true"/>}{span_text}
                </p>
                {failed
                    and <Alert variant="destructive">
                        <AlertDescription>{failed}</AlertDescription>
                    </Alert>}
            </div>
            <section aria-labelledby="money-heading" className="flex flex-col gap-4">
                <div className="flex flex-col gap-1">
                    <h2 id="money-heading" className="text-lg font-semibold">
                        Money taken
                    </h2>
                    <p className="text-sm text-muted-foreground">
                        Counted on the day the money came in, {span_text}.
                    </p>
                </div>
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
                    <KpiTile
                        label="Net takings"
                        value={money_label(takings["net_cents"], currency)}
                        note="After refunds and adjustments"
                        testid="kpi-net"
                    />
                    <KpiTile
                        label="Gross"
                        value={money_label(takings["gross_cents"], currency)}
                        note={f"Refunds {money_label(
                            takings['refunds_cents'], currency
                        )}"}
                        testid="kpi-gross"
                    />
                    <KpiTile
                        label="M-Pesa"
                        value={money_label(takings["mpesa_cents"], currency)}
                        note={f"Cash {money_label(takings['cash_cents'], currency)}"}
                        testid="kpi-mpesa"
                    />
                    <KpiTile
                        label="At the box office"
                        value={money_label(takings["counter_cents"], currency)}
                        note={f"Online {money_label(
                            takings['online_cents'], currency
                        )}"}
                        testid="kpi-counter"
                    />
                </div>
                <div className="rounded-xl bg-card p-4 ring-1 ring-foreground/10">
                    <TakingsChart
                        points={sales["chart"]["points"]}
                        unit={sales["chart"]["unit"]}
                        currency={currency}
                    />
                </div>
            </section>
            <section aria-labelledby="shows-heading" className="flex flex-col gap-4">
                <div className="flex flex-col gap-1">
                    <h2 id="shows-heading" className="text-lg font-semibold">
                        Showtimes in this period
                    </h2>
                    <p className="text-sm text-muted-foreground">
                        Counted on the day the showtime starts; tickets bought earlier count here too.
                    </p>
                </div>
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
                    <KpiTile
                        label="Tickets sold"
                        value={f"{shown['tickets_sold']}"}
                        note={f"{shown['tickets_scanned']} scanned at the door"}
                        testid="kpi-tickets"
                    />
                    <KpiTile
                        label="Occupancy"
                        value={percent(full)}
                        note={f"{shown['seats_on_sale']} seats on sale, {shown[
                            'showtimes'
                        ]} showtimes"}
                        testid="kpi-occupancy"
                    />
                    <KpiTile
                        label="Average ticket"
                        value={money_label(shown["average_ticket_cents"], currency)}
                        note="Booking fee included"
                        testid="kpi-average"
                    />
                    <KpiTile
                        label="Ticket revenue"
                        value={money_label(shown["ticket_revenue_cents"], currency)}
                        note={f"{money_label(
                            shown['revenue_per_seat_cents'], currency
                        )} per seat on sale"}
                        testid="kpi-revenue"
                    />
                </div>
                <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
                    <div
                        className="flex flex-col gap-3 rounded-xl bg-card p-4 ring-1 ring-foreground/10"
                    >
                        <h3 className="text-sm font-medium">Top movies</h3>
                        <TopMovies rows={sales["top_movies"]} currency={currency}/>
                    </div>
                    <div className="flex flex-col gap-3">
                        <h3 className="text-sm font-medium">
                            By venue, screen, movie and showtime
                        </h3>
                        <DrillDown
                            venues={sales["venues"]}
                            currency={currency}
                            timezone={sales["timezone"]}
                        />
                    </div>
                </div>
            </section>
        </div>;
}
