"""Which payment provider the app uses (P5.1, P5.2; ADR-0015, ADR-0016).

Set by AFRICINEMAS_PAYMENTS: "simulator" (tests, demos) or "daraja" (M-Pesa through
Safaricom, with the DARAJA_* settings; DARAJA_BASE_URL defaults to the sandbox).
There is no default: a server that doesn't say refuses to take payments rather than
quietly faking them (a forgotten setting must never mean free tickets), and "daraja"
with a setting missing is refused too, naming the missing settings, never their values.
Without a ticket signing key (AFRICINEMAS_TICKET_KEY, P6.1) payments are refused as well,
so nobody pays for tickets the server can't issue.
Each provider is one instance per process: the simulator's pushes and the Daraja login
token are shared by every request.
"""

import os;
import from core.payments.provider { PaymentProvider }
import from core.payments.simulator { SimulatedProvider }
import from core.payments.daraja { DarajaConfig, DarajaProvider, SANDBOX_URL }
import from core.booking.ticket_codes { ticket_key, TicketKeyMissing }

glob PAYMENTS_ENV: str = "AFRICINEMAS_PAYMENTS",
     DARAJA_SETTINGS: list[str] = [
         "DARAJA_CONSUMER_KEY",
         "DARAJA_CONSUMER_SECRET",
         "DARAJA_SHORTCODE",
         "DARAJA_PASSKEY"
     ],
     _MADE: dict[str, PaymentProvider] = {};

class ProviderNotConfigured(RuntimeError) {}

def _daraja -> DarajaProvider {
    missing = [
        name
        for name in DARAJA_SETTINGS
        if not os.environ.get(name, "").strip()
    ];
    if missing {
        raise ProviderNotConfigured(
            f"M-Pesa (Daraja) needs these settings: {', '.join(missing)}."
        );
    }
    return DarajaProvider(
        config=DarajaConfig(
            consumer_key=os.environ["DARAJA_CONSUMER_KEY"].strip(),
            consumer_secret=os.environ["DARAJA_CONSUMER_SECRET"].strip(),
            shortcode=os.environ["DARAJA_SHORTCODE"].strip(),
            passkey=os.environ["DARAJA_PASSKEY"].strip(),
            base_url=os.environ.get("DARAJA_BASE_URL", "").strip() or SANDBOX_URL,
            transaction_type=os.environ.get("DARAJA_TRANSACTION_TYPE", "").strip()
                or "CustomerPayBillOnline"
        )
    );
}

def payment_provider -> PaymentProvider {
    mode = os.environ.get(PAYMENTS_ENV, "").strip().lower();
    if mode not in ["simulator", "daraja"] {
        raise ProviderNotConfigured(
            f"Set {PAYMENTS_ENV} to choose a payment provider ('simulator' or 'daraja')."
        );
    }
    try {
        # A paid order gets signed tickets (P6.1): no key, no payments, so nobody pays
        # for tickets the server can't issue.
        ticket_key();
    } except TicketKeyMissing as e {
        raise ProviderNotConfigured(str(e)) from e;
    }
    if mode not in _MADE {
        _MADE[mode] = SimulatedProvider() if mode == "simulator" else _daraja();
    }
    return _MADE[mode];
}
