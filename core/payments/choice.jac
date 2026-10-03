"""Which payment provider the app uses (P5.1; ADR-0015).

Set by AFRICINEMAS_PAYMENTS: "simulator" (tests, demos) or, from plan 5.2, "daraja".
There is no default: a server that doesn't say refuses to take payments rather than
quietly faking them (a forgotten setting must never mean free tickets). The simulator
is one instance per process, so its pushes and callbacks are shared by every request.
"""

import os;
import from core.payments.provider { PaymentProvider }
import from core.payments.simulator { SimulatedProvider }

glob PAYMENTS_ENV: str = "AFRICINEMAS_PAYMENTS",
     _MADE: dict[str, SimulatedProvider] = {};

class ProviderNotConfigured(RuntimeError) {}

def payment_provider -> PaymentProvider {
    mode = os.environ.get(PAYMENTS_ENV, "").strip().lower();
    if mode == "simulator" {
        if "simulator" not in _MADE {
            _MADE["simulator"] = SimulatedProvider();
        }
        return _MADE["simulator"];
    }
    raise ProviderNotConfigured(
        f"Set {PAYMENTS_ENV} to choose a payment provider ('simulator' for now)."
    );
}
