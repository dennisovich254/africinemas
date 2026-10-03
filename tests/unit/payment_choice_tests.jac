"""P5.1: choosing the payment provider (core/payments/choice.jac).

There is no default: without AFRICINEMAS_PAYMENTS the app refuses to take payments,
so a forgotten setting can never mean free tickets. The simulator is one per process.
"""

import os;
import from core.payments.choice {
    PAYMENTS_ENV,
    ProviderNotConfigured,
    payment_provider
}
import from core.payments.simulator { SimulatedProvider }

def _refused -> bool {
    try {
        payment_provider();
    } except ProviderNotConfigured {
        return True;
    }
    return False;
}

test "without a choice, or with an unknown one, payments are refused" {
    before = os.environ.pop(PAYMENTS_ENV, None);
    try {
        assert _refused();
        os.environ[PAYMENTS_ENV] = "paypal";
        assert _refused();
    } finally {
        os.environ.pop(PAYMENTS_ENV, None);
        if before is not None {
            os.environ[PAYMENTS_ENV] = before;
        }
    }
}

test "the simulator is one instance for the whole process" {
    before = os.environ.get(PAYMENTS_ENV);
    os.environ[PAYMENTS_ENV] = "Simulator";
    try {
        first = payment_provider();
        assert isinstance(first, SimulatedProvider);
        assert payment_provider() is first;
    } finally {
        os.environ.pop(PAYMENTS_ENV, None);
        if before is not None {
            os.environ[PAYMENTS_ENV] = before;
        }
    }
}
