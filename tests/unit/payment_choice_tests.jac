"""P5.1: choosing the payment provider (core/payments/choice.jac).

There is no default: without AFRICINEMAS_PAYMENTS the app refuses to take payments,
so a forgotten setting can never mean free tickets. The simulator is one per process.
"""

import os;
import from core.payments.choice {
    PAYMENTS_ENV,
    ProviderNotConfigured,
    payment_provider,
    _MADE
}
import from core.payments.daraja { DarajaProvider }
import from core.payments.simulator { SimulatedProvider }
import from core.booking.ticket_codes { KEY_ENV }

glob TICKET_KEY: str = "unit-test-ticket-key-0123456789abcdef";

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

test "without a ticket key, payments are refused: nobody pays for no ticket (P6.1)" {
    before = os.environ.get(PAYMENTS_ENV);
    key_before = os.environ.pop(KEY_ENV, None);
    os.environ[PAYMENTS_ENV] = "simulator";
    try {
        message = "";
        try {
            payment_provider();
        } except ProviderNotConfigured as e {
            message = str(e);
        }
        assert KEY_ENV in message , message;
    } finally {
        os.environ.pop(PAYMENTS_ENV, None);
        if before is not None {
            os.environ[PAYMENTS_ENV] = before;
        }
        if key_before is not None {
            os.environ[KEY_ENV] = key_before;
        }
    }
}

test "the simulator is one instance for the whole process" {
    before = os.environ.get(PAYMENTS_ENV);
    os.environ[PAYMENTS_ENV] = "Simulator";
    os.environ[KEY_ENV] = TICKET_KEY;
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

test "daraja needs all its settings, says which are missing, and never echoes values" {
    names = [
        PAYMENTS_ENV,
        "DARAJA_CONSUMER_KEY",
        "DARAJA_CONSUMER_SECRET",
        "DARAJA_SHORTCODE",
        "DARAJA_PASSKEY",
        "DARAJA_BASE_URL"
    ];
    before = {n: os.environ.get(n) for n in names};
    try {
        for n in names {
            os.environ.pop(n, None);
        }
        os.environ[PAYMENTS_ENV] = "daraja";
        os.environ[KEY_ENV] = TICKET_KEY;
        os.environ["DARAJA_CONSUMER_KEY"] = "key-SECRETISH-1";
        os.environ["DARAJA_SHORTCODE"] = "174379";
        message = "";
        try {
            payment_provider();
        } except ProviderNotConfigured as e {
            message = str(e);
        }
        assert "DARAJA_CONSUMER_SECRET" in message and "DARAJA_PASSKEY" in message;
        assert "DARAJA_SHORTCODE" not in message and "key-SECRETISH-1" not in message;
        os.environ["DARAJA_CONSUMER_SECRET"] = "secret-1";
        os.environ["DARAJA_PASSKEY"] = "passkey-1";
        made = payment_provider();
        assert isinstance(made, DarajaProvider);
        assert made.config.base_url == "https://sandbox.safaricom.co.ke";
        assert payment_provider() is made;
    } finally {
        _MADE.pop("daraja", None);
        for n in names {
            os.environ.pop(n, None);
            if before[n] is not None {
                os.environ[n] = before[n];
            }
        }
    }
}
