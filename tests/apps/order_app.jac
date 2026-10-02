"""Test-only app entry for the order races (P4.5) and the hold load test (P4.7, load/).
Never imported by main.jac.

The production endpoints a priced, held showtime and its orders need, without the web
client, plus a probe counting a showtime's orders.
"""

import from core.tenancy.signup { create_cinema }  # jac:ignore[W2037]
import from core.tenancy.tenant_api { start_shift }  # jac:ignore[W2037]
import from core.catalog.venue_api { create_venue, create_auditorium }  # jac:ignore[W2037]
import from core.catalog.layout_api { save_layout, publish_layout }  # jac:ignore[W2037]
import from core.catalog.movie_api { create_movie }  # jac:ignore[W2037]
import from core.catalog.screening_api {
    create_screening,  # jac:ignore[W2037]
    schedule_screening,  # jac:ignore[W2037]
    publish_screening  # jac:ignore[W2037]
}
import from core.catalog.pricing_api { save_price_list }  # jac:ignore[W2037]
import from core.booking.hold_api { hold_seats }  # jac:ignore[W2037]
import from core.catalog.storefront_api { public_seat_availability }  # jac:ignore[W2037]
import from core.booking.order_api { place_order, my_order }  # jac:ignore[W2037]
import from core.tenancy.open_cinema { open_cinema }
import from core.tenancy.principal { node_id, act_as, restore }
import from core.catalog.venues { find_screening }
import from core.booking.models { Order }

def:pub count_orders(slug: str, screening_id: str) -> int {
    cinema = open_cinema(slug);
    assert cinema is not None;
    screening = find_screening(cinema, screening_id);
    assert screening is not None;
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = len([screening-->[?:Order]]);
    } finally {
        restore(me);
    }
    return found;
}
