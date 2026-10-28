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

Each cinema's own M-Pesa (P15.3, ADR-0082): a payment is made with the account the
cinema had in use when it started (PaymentIntent.mpesa_version) and always checked with
the same one. provider_for(cinema, version) gives that account's Daraja provider, its
keys opened on the server, one per account version per process, against DARAJA_BASE_URL;
with the simulator, the shared simulator (each push records the paybill or till it went
to). Version 0 is "no account of the cinema's": the platform's DARAJA_* app, only for
the sandbox and tests. Against live Daraja, or with AFRICINEMAS_OWN_MPESA=required, a
cinema without its own account can't take M-Pesa: AfriCinemas never collects a cinema's
money in its own paybill (it isn't licensed to hold other people's money).
"""

import os;
import from core.payments.provider { PaymentProvider }
import from core.payments.simulator { SimulatedProvider }
import from core.payments.daraja { DarajaConfig, DarajaProvider, SANDBOX_URL }
import from core.booking.ticket_codes { ticket_key, TicketKeyMissing }
import from core.tenancy.models { Tenant }
import from core.payments.mpesa_account {
    MpesaAccount,
    active_account,
    account_version,
    config_of,
    pays_to
}
import from core.payments.secret_box { SealingKeyMissing, CannotOpen }

glob PAYMENTS_ENV: str = "AFRICINEMAS_PAYMENTS",
     OWN_ENV: str = "AFRICINEMAS_OWN_MPESA",
     DARAJA_SETTINGS: list[str] = [
         "DARAJA_CONSUMER_KEY",
         "DARAJA_CONSUMER_SECRET",
         "DARAJA_SHORTCODE",
         "DARAJA_PASSKEY"
     ],
     _MADE: dict[str, PaymentProvider] = {},
     _CINEMAS: dict[str, PaymentProvider] = {};

class ProviderNotConfigured(RuntimeError) {}

class NotConnected(ProviderNotConfigured) {}

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

def _mode -> str {
    return os.environ.get(PAYMENTS_ENV, "").strip().lower();
}

def base_url -> str {
    return os.environ.get("DARAJA_BASE_URL", "").strip() or SANDBOX_URL;
}

def own_account_required -> bool {
    # Whether each cinema must use its own M-Pesa: always against live Daraja.
    return os.environ.get(OWN_ENV, "").strip().lower() == "required"
        or (_mode() == "daraja" and base_url().rstrip("/") != SANDBOX_URL);
}

def version_for_new(cinema: Tenant) -> int {
    # The account a payment starting now uses: the cinema's account in use, or 0 (the
    # platform's test app), refused when the cinema must have its own.
    active = active_account(cinema);
    if active is not None {
        return active.version;
    }
    if own_account_required() {
        raise NotConnected(f"{cinema.name} hasn't connected its M-Pesa yet.");
    }
    return 0;
}

def account_provider(account: MpesaAccount) -> PaymentProvider {
    # The provider for one of a cinema's accounts (its test payment, its payments).
    shared = payment_provider();
    if _mode() == "simulator" {
        return shared;
    }
    key = f"{account.tenant_id}:{account.version}";
    if key not in _CINEMAS {
        try {
            _CINEMAS[key] = DarajaProvider(config=config_of(account, base_url()));
        } except (SealingKeyMissing, CannotOpen) as e {
            raise ProviderNotConfigured(
                "This cinema's M-Pesa keys can't be read on this server."
            ) from e;
        }
    }
    return _CINEMAS[key];
}

def provider_for(cinema: Tenant, version: int) -> PaymentProvider {
    # The provider a payment made with account `version` is sent and checked with.
    if version == 0 {
        if own_account_required() {
            raise NotConnected(f"{cinema.name} hasn't connected its M-Pesa yet.");
        }
        return payment_provider();
    }
    account = account_version(cinema, version);
    if account is None {
        raise ProviderNotConfigured("This payment's M-Pesa account is missing.");
    }
    return account_provider(account);
}

def shortcode_for(cinema: Tenant, version: int) -> str {
    # Where a payment made with account `version` goes ("" for the platform's).
    account = account_version(cinema, version) if version else None;
    return pays_to(account) if account is not None else "";
}
