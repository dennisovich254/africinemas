"""Each cinema's own M-Pesa (P15.3, ADR-0082): the paybill or till its payments go to.

A cinema connects its own Daraja app (Settings -> Payments): a Paybill (its number) or
a Till (the store number Daraja signs with, and the till number the money goes to),
the registered name, and the app's consumer key, consumer secret and passkey. The three
keys are kept only sealed (core/payments/secret_box.jac, bound to the cinema, the
version and the field) and never leave the server again: views show the last four
characters of the consumer key, nothing more.

Every connection is a new MpesaAccount version, never an edit, so a payment always
knows which keys it was made with (PaymentIntent.mpesa_version) and is checked with
them, even after a switch. A version's state:
- "testing": saved; a KES 1 test payment must go through before it's used;
- "ready": the test went through; it's in use from `active_from`: at once for a first
  connection, 24 hours (CHANGE_WAIT_S) after it was asked for when it replaces another,
  so an owner whose account was taken over has time to cancel;
- "cancelled": an owner cancelled it before it was in use.
The account in use is the latest ready version whose active_from has come. The nodes
belong to the cinema's principal alone and aren't granted to its staff: only the
server, acting for the cinema, reads them.
"""

import from datetime { datetime, timedelta }
import from core.clock { now }
import from core.tenancy.models { Tenant }
import from core.tenancy.principal { node_id, act_as, restore, flush_now }
import from core.payments.daraja { DarajaConfig }
import from core.payments.secret_box { seal, open_sealed }

glob CHANGE_WAIT_S: int = 24 * 60 * 60,
     KEYS: list[str] = ["consumer_key", "consumer_secret", "passkey"];

node MpesaAccount {
    has tenant_id: str,
        version: int,
        kind: str,
        shortcode: str,
        till_number: str = "",
        registered_name: str = "",
        sealed: dict[str, str] = {},
        key_hint: str = "",
        state: str = "testing",
        replaces: int = 0,
        created_at: str = "",
        created_by: str = "",
        test_checkout_id: str = "",
        test_text: str = "",
        tested_at: str = "",
        active_from: str = "",
        cancelled_at: str = "",
        cancelled_by: str = "";
}

def _context(tenant_id: str, version: int, field: str) -> str {
    return f"mpesa|{tenant_id}|{version}|{field}";
}

def accounts_of(cinema: Tenant) -> list[MpesaAccount] {
    # Every version, oldest first.
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = [cinema-->[?:MpesaAccount]];
    } finally {
        restore(me);
    }
    return sorted(found, key=lambda (a: MpesaAccount) -> int { return a.version; });
}

def in_use(account: MpesaAccount) -> bool {
    return account.state == "ready"
        and bool(account.active_from)
        and datetime.fromisoformat(account.active_from) <= now();
}

def active_account(cinema: Tenant) -> MpesaAccount | None {
    # The account payments go to now, or None.
    found: MpesaAccount | None = None;
    for a in accounts_of(cinema) {
        if in_use(a) {
            found = a;
        }
    }
    return found;
}

def pending_account(cinema: Tenant) -> MpesaAccount | None {
    # The newest version not in use yet and not cancelled (being tested, or waiting
    # out the change's 24 hours), if it's newer than the one in use.
    active = active_account(cinema);
    newest: MpesaAccount | None = None;
    for a in accounts_of(cinema) {
        if a.state != "cancelled" and not in_use(a) {
            newest = a;
        }
    }
    if newest is None or (active is not None and newest.version < active.version) {
        return None;
    }
    return newest;
}

def account_version(cinema: Tenant, version: int) -> MpesaAccount | None {
    for a in accounts_of(cinema) {
        if a.version == version {
            return a;
        }
    }
    return None;
}

def pays_to(account: MpesaAccount) -> str {
    # The number customers' money goes to: the till for a Till, else the paybill.
    return account.till_number if account.kind == "till" else account.shortcode;
}

def add_account(
    cinema: Tenant,
    kind: str,
    shortcode: str,
    till_number: str,
    registered_name: str,
    keys: dict[str, str],
    created_by: str
) -> MpesaAccount {
    # A new version, being tested; any other version not yet in use is cancelled.
    versions = accounts_of(cinema);
    active = active_account(cinema);
    tenant_id = node_id(cinema);
    version = (versions[-1].version if versions else 0) + 1;
    stamp = now().isoformat();
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        for a in versions {
            if a.state != "cancelled" and not in_use(a) {
                a.state = "cancelled";
                a.cancelled_at = stamp;
                a.cancelled_by = created_by;
            }
        }
        made = MpesaAccount(
            tenant_id=tenant_id,
            version=version,
            kind=kind,
            shortcode=shortcode,
            till_number=till_number,
            registered_name=registered_name,
            sealed={
                field: seal(keys[field], _context(tenant_id, version, field))
                for field in KEYS
            },
            key_hint=keys["consumer_key"][-4:],
            replaces=active.version if active is not None else 0,
            created_at=stamp,
            created_by=created_by
        );
        cinema ++> made;
        flush_now();
    } finally {
        restore(me);
    }
    return made;
}

def update_account(cinema: Tenant, account: MpesaAccount, changes: dict[str, str]) {
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        for (field, value) in changes.items() {
            setattr(account, field, value);
        }
        flush_now();
    } finally {
        restore(me);
    }
}

def passed_test(cinema: Tenant, account: MpesaAccount) {
    # The KES 1 test went through: in use at once, or, replacing another account, 24
    # hours after the change was asked for.
    stamp = now();
    starts = stamp;
    if account.replaces {
        waited = datetime.fromisoformat(account.created_at)
            + timedelta(seconds=CHANGE_WAIT_S);
        starts = max(stamp, waited);
    }
    update_account(
        cinema,
        account,
        {
            "state": "ready",
            "tested_at": stamp.isoformat(),
            "active_from": starts.isoformat()
        }
    );
}

def config_of(account: MpesaAccount, base_url: str) -> DarajaConfig {
    # The account's Daraja settings, its keys opened (only ever on the server).
    opened = {
        field: open_sealed(
            account.sealed[field], _context(account.tenant_id, account.version, field)
        ) for field in KEYS
    };
    till = account.kind == "till";
    return DarajaConfig(
        consumer_key=opened["consumer_key"],
        consumer_secret=opened["consumer_secret"],
        shortcode=account.shortcode,
        passkey=opened["passkey"],
        base_url=base_url,
        transaction_type="CustomerBuyGoodsOnline" if till else "CustomerPayBillOnline",
        party_b=account.till_number if till else ""
    );
}

def account_view(account: MpesaAccount) -> dict[str, any] {  # jac:ignore[W1037]
    # What the back office sees: never a key, only the consumer key's last four.
    return {
        "version": account.version,
        "kind": account.kind,
        "shortcode": account.shortcode,
        "till_number": account.till_number,
        "pays_to": pays_to(account),
        "registered_name": account.registered_name,
        "key_hint": account.key_hint,
        "state": account.state,
        "in_use": in_use(account),
        "is_change": account.replaces > 0,
        "created_at": account.created_at,
        "created_by": account.created_by,
        "test_text": account.test_text,
        "tested_at": account.tested_at,
        "active_from": account.active_from
    };
}
