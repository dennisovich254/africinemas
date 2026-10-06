"""Test-only app entry for starting payments (P5.3). Never imported by main.jac.

The production endpoints a priced showtime, a hold, an order and a payment need, plus
probes into the simulated M-Pesa (how many prompts a payment caused, a scripted outcome
per phone number) and the payments stored for a showtime. Run with
AFRICINEMAS_PAYMENTS=simulator.
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
import from core.catalog.storefront_api { public_seat_availability }  # jac:ignore[W2037]
import from core.booking.hold_api { hold_seats }  # jac:ignore[W2037]
import from core.booking.order_api { place_order, my_order }  # jac:ignore[W2037]
import from core.payments.payment_api { start_payment, my_payment }  # jac:ignore[W2037]
import from core.tenancy.open_cinema { open_cinema }
import from core.tenancy.principal { node_id, act_as, restore }
import from core.catalog.venues { find_screening }
import from core.booking.models { Order }
import from core.payments.models { PaymentIntent }
import from core.payments.choice { payment_provider }
import from core.payments.simulator { SimulatedProvider }

def _simulator -> SimulatedProvider {
    made = payment_provider();
    assert isinstance(made, SimulatedProvider);
    return made as SimulatedProvider;
}

def:pub pay_push_count(reference: str) -> int {
    return _simulator().push_count(reference);
}

def:pub pay_script(phone: str, outcome: str) -> bool {
    _simulator().outcomes[phone] = outcome;
    return True;
}

def:pub pay_stored(slug: str, screening_id: str) -> list[list[str]] {
    # Every payment stored for the showtime: [reference, state], oldest first.
    cinema = open_cinema(slug);
    assert cinema is not None;
    screening = find_screening(cinema, screening_id);
    assert screening is not None;
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found: list[PaymentIntent] = [];
        for o in [screening-->[?:Order]] {
            for p in [o-->[?:PaymentIntent]] {
                found.append(p);
            }
        }
    } finally {
        restore(me);
    }
    ordered = sorted(
        found,
        key=lambda (p: PaymentIntent) -> str { return p.created_at; }  # jac:ignore[W1037]
    );
    return [[p.reference, p.state] for p in ordered];
}
