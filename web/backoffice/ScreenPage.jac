"""`/app/:slug/screens/:auditorium_id`: one screen, in tabs (2026-10-30).

- Seat layout: the designer (SeatDesigner).
- Counter seats, for staff who configure seats: the seats kept for the counter on every
  showtime here (CounterSeatsEditor; core/booking/counter_seats.jac). It needs a
  published layout.
"""

import from react { useState }
import from core.catalog.screening_api {
    screen_counter_seats,  # jac:ignore[W2037] authenticated endpoint
    set_screen_counter_seats  # jac:ignore[W2037] authenticated endpoint
}
import from ..shell.Tabs { Tabs }
import from .SeatDesigner { SeatDesigner }
import from .CounterSeatsEditor { CounterSeatsEditor }

def:pub ScreenPage(
    slug: str, auditorium_id: str, permissions: list[str]
) -> JsxElement {
    [tab, set_tab] = useState("layout");
    may_set: bool = "seats.configure" in permissions;

    async def load -> any {  # jac:ignore[W1037]
        return await screen_counter_seats(slug, auditorium_id);  # jac:ignore[W2037]
    }

    async def save(labels: list[str]) -> any {  # jac:ignore[W1037]
        return await set_screen_counter_seats(slug, auditorium_id, labels);  # jac:ignore[W2037]
    }

    if not may_set {
        return
            <SeatDesigner
                slug={slug}
                auditorium_id={auditorium_id}
                permissions={permissions}
            />;
    }
    return
        <div className="flex flex-col gap-5">
            <Tabs
                label="Screen"
                tabs={[
                    {"key": "layout", "label": "Seat layout", "count": ""},
                    {"key": "counter", "label": "Counter seats", "count": ""}
                ]}
                current={tab}
                on_pick={set_tab}
                testid="screen-tab"
            />
            {tab == "layout"
                and <SeatDesigner
                    slug={slug}
                    auditorium_id={auditorium_id}
                    permissions={permissions}
                />}
            {tab == "counter"
                and <CounterSeatsEditor
                    load={load}
                    save={save}
                    note="Tick the seats your counter sells, on paper or by phone. Online customers can't book them, so you never sell a seat twice. Unsold ones go on sale online before each showtime, at the time set in Settings → Box office. A showtime can change them on the Screenings page."
                    testid="screen-counter-seats"
                />}
        </div>;
}
