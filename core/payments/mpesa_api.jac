"""Settings -> Payments: connecting a cinema's own M-Pesa (P15.3, ADR-0082).

- mpesa_settings(tenant): for staff who change settings; the account in use, any change
  waiting (being tested, or waiting out its 24 hours), whether this member may change
  it (the owner) and why the cinema can't connect yet, if it can't. Never a key.
- connect_mpesa(...): the owner only (tenant.verification), with their password again.
  Only a cinema AfriCinemas has verified (P14.5) connects, and the registered name must
  be the verified business's. The keys are sealed at once (core/payments/secret_box.jac)
  and never returned. Every connection is emailed to the cinema's owners, so one they
  didn't make is seen; one replacing the account in use waits 24 hours.
- test_mpesa(tenant, phone): a KES 1 payment from the owner's phone to the new paybill
  or till, sent with the new keys. mpesa_test_status(tenant) asks M-Pesa how it went;
  once it went through, the account is in use (at once, or when the 24 hours are up).
- cancel_mpesa_change(tenant): the owner cancels a connection not yet in use.

Every parameter is required (JI-060). Connecting, test payments and cancelling are in
the cinema's audit log.
"""

import os;
import re;
import json;
import html;
import secrets;
import from email.utils { formataddr }
import from core.clock { now }
import from core.claims { claim, release, claims_in }
import from core.authz.context { scoped }
import from core.authz.policy { Resource, require }
import from core.catalog.answers { Refused, answer }
import from core.audit.log { audited }
import from core.tenancy.models { Tenant }
import from core.tenancy.principal { fresh_node_id }
import from jaclang { JacRuntime as Jac }
import from core.tenancy.identity { verified_sign_in }
import from core.tenancy.verification { verified_at, record_of }
import from core.platform.cinemas_api { owners_of }
import from core.notify.mailer { OutgoingMail, send, from_address }
import from core.site { main_address }
import from core.payments.phone { msisdn, InvalidPhone }
import from core.payments.provider { StkRequest }
import from core.payments.state { PaymentState }
import from core.payments.payment_api { callback_url }
import from core.payments.choice { account_provider, ProviderNotConfigured }
import from core.payments.secret_box { sealing_ready }
import from core.payments.setup_help { guide_video }
import from core.payments.mpesa_account {
    CHANGE_WAIT_S,
    MpesaAccount,
    active_account,
    pending_account,
    add_account,
    update_account,
    passed_test,
    pays_to,
    account_view
}
import from core.platform.jobs { ran }

glob OWNER: str = "tenant.verification",
     SETTINGS: str = "tenant.settings.update",
     TEST_CENTS: int = 100,
     MAIL_QUEUE: str = "mpesa-change-mail",
     SENDING: str = "mpesa-change-sending",
     SENDING_S: int = 120,
     MAIL_SECONDS: int = int(os.environ.get("AFRICINEMAS_MAIL_SECONDS", "5")),
     NUMBER: re.Pattern[str] = re.compile(r"^[0-9]{5,7}$"),
     KEY_TEXT: re.Pattern[str] = re.compile(r"^[A-Za-z0-9+/=_-]{8,200}$"),
     SUFFIXES: dict[str, str] = {"limited": "ltd", "company": "co", "and": "&"};

def same_name(one: str, other: str) -> bool {
    # Whether two business names are the same, ignoring case, punctuation and how
    # "Limited" or "Company" is written.
    def tidy(text: str) -> str {
        words = re.sub(r"[^a-z0-9& ]", " ", text.lower().replace("'", "")).split();
        return " ".join([SUFFIXES.get(w, w) for w in words]);
    }
    return bool(tidy(one)) and tidy(one) == tidy(other);
}

def _may(scope: any, action: str) -> bool {  # jac:ignore[W1037]
    try {
        require(scope.ctx, action, Resource(tenant_id=scope.ctx.tenant_id));
    } except Exception {
        return False;
    }
    return True;
}

def _blocked(cinema: Tenant) -> str {
    # Why the cinema can't connect M-Pesa yet ("" if it can).
    if not verified_at(cinema) {
        return "not_verified";
    }
    if not sealing_ready() {
        return "not_ready";
    }
    return "";
}

def _settings(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, SETTINGS);
    cinema = scope.tenant;
    active = active_account(cinema);
    pending = pending_account(cinema);
    return {
        "ok": True,
        "active": account_view(active) if active is not None else None,
        "pending": account_view(pending) if pending is not None else None,
        "may_change": _may(scope, OWNER),
        "blocked": _blocked(cinema),
        "verified_name": record_of(cinema)["details"].get("registered_name", "")
            if _may(scope, OWNER)
            else "",
        "wait_hours": CHANGE_WAIT_S // 3600,
        # AfriCinemas' setup video, if one is set (core/payments/setup_help.jac).
        "guide_video": guide_video()
    };
}

def _password_checked(sign_in: str, password: str) -> str {
    # The caller's sign-in name, once their password is checked again.
    mine = verified_sign_in(sign_in) if sign_in else "";
    if not mine {
        raise Refused("not_you", "Sign out and back in, then try again.");
    }
    if not isinstance(password, str) or not password {
        raise Refused("wrong_password", "Enter your password.");
    }
    users: any = Jac.get_user_manager(Jac.get_context().base_path_dir or "");  # jac:ignore[W1037]
    try {
        found = users.authenticate(mine, password, "mpesa");
    } except Exception {
        raise Refused(
            "too_many_tries", "Too many tries. Wait a few minutes, then try again."
        );
    }
    if not found {
        raise Refused("wrong_password", "That isn't your password.");
    }
    return mine;
}

def _clean_keys(keys: any) -> dict[str, str] {  # jac:ignore[W1037]
    if not isinstance(keys, dict) {
        keys = {};
    }
    labels = {
        "consumer_key": "consumer key",
        "consumer_secret": "consumer secret",
        "passkey": "passkey"
    };
    clean: dict[str, str] = {};
    for (field, label) in labels.items() {
        value = keys.get(field, "");
        value = value.strip() if isinstance(value, str) else "";
        if not KEY_TEXT.match(value) {
            raise Refused(
                "invalid_keys",
                f"Paste the {label} exactly as Daraja shows it, without spaces."
            );
        }
        clean[field] = value;
    }
    return clean;
}

def queue_mail(cinema: Tenant, account: MpesaAccount) {
    # Every owner hears of every connection, so one they didn't make is seen in time.
    office = f"{main_address()}/app/{cinema.slug}/settings/payments";
    if account.replaces {
        subject = f"{cinema.name}: your M-Pesa is being changed";
        lead = f"Someone asked for {cinema.name}'s M-Pesa payments to go to {account.kind} {pays_to(
            account
        )} ({account.registered_name}). If its test payment goes through, the change is made {CHANGE_WAIT_S
            // 3600} hours after it was asked for; until then payments keep going to the paybill or till you use now.";
    } else {
        subject = f"{cinema.name}: M-Pesa is being connected";
        lead = f"Someone asked for {cinema.name}'s M-Pesa payments to go to {account.kind} {pays_to(
            account
        )} ({account.registered_name}). It's used once its test payment goes through.";
    }
    warn = "If this wasn't you, cancel it on the Payments page now, change your password and write to help@africinemas.co.ke.";
    text = f"{lead}\n\n{warn}\n\nPayments: {office}\n\nAfriCinemas\n";
    body = f'<p>{html.escape(lead)}</p><p><strong>{html.escape(
        warn
    )}</strong></p><p><a href="{html.escape(office)}">Open the Payments page</a></p>';
    for address in owners_of(cinema) {
        claim(
            MAIL_QUEUE,
            fresh_node_id(),
            json.dumps({"to": address, "subject": subject, "text": text, "html": body})
        );
    }
}

def send_mail_due -> int {
    # Sends every queued email; returns how many went.
    sent = 0;
    for (key, queued, _) in claims_in(MAIL_QUEUE) {
        mine = fresh_node_id();
        if claim(SENDING, key, mine, SENDING_S) != mine {
            continue;
        }
        try {
            mail = json.loads(queued);
            if send(
                OutgoingMail(
                    to=mail["to"],
                    sender=formataddr(("AfriCinemas", from_address())),
                    subject=mail["subject"],
                    text=mail["text"],
                    html=mail["html"]
                )
            ) {
                release(MAIL_QUEUE, key, queued);
                sent += 1;
            }
        } finally {
            release(SENDING, key, mine);
        }
    }
    return sent;
}

@schedule(trigger=ScheduleTrigger.STATIC, interval=MAIL_SECONDS)
def send_mpesa_mail {
    ran("send_mpesa_mail", MAIL_SECONDS);
    # Runs as Jac's system identity on every server copy; SENDING keeps one per email.
    send_mail_due();
}

def _connect(  # jac:ignore[W3030] the account's details, its keys and the password
    tenant: str,
    kind: str,
    shortcode: str,
    till_number: str,
    registered_name: str,
    keys: any,  # jac:ignore[W1037]
    password: str,
    sign_in: str
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, OWNER);
    cinema = scope.tenant;
    blocked = _blocked(cinema);
    if blocked == "not_verified" {
        raise Refused(
            "not_verified",
            "AfriCinemas verifies your business first. Then you can connect M-Pesa."
        );
    }
    if blocked {
        raise Refused(
            "not_ready", "Connecting M-Pesa isn't available right now. Try again later."
        );
    }
    if kind not in ["paybill", "till"] {
        raise Refused("invalid_kind", "Choose a Paybill or a Till.");
    }
    number = shortcode.strip() if isinstance(shortcode, str) else "";
    till = till_number.strip() if isinstance(till_number, str) else "";
    if not NUMBER.match(number) {
        raise Refused(
            "invalid_shortcode",
            (
                "Enter the paybill number"
                    if kind == "paybill"
                    else "Enter the store number"
            )
                + " (5 to 7 digits)."
        );
    }
    if kind == "till" and not NUMBER.match(till) {
        raise Refused("invalid_till", "Enter the till number (5 to 7 digits).");
    }
    name = " ".join(registered_name.split())
        if isinstance(registered_name, str)
        else "";
    verified = record_of(cinema)["details"].get("registered_name", "");
    if not same_name(name, verified) {
        raise Refused(
            "name_mismatch",
            f"The paybill or till must be registered to {verified}, the business AfriCinemas verified."
        );
    }
    clean = _clean_keys(keys);
    who = _password_checked(sign_in, password);
    made = add_account(
        cinema, kind, number, till if kind == "till" else "", name, clean, who
    );
    queue_mail(cinema, made);
    return _settings(tenant);
}

def _waiting(cinema: Tenant) -> MpesaAccount {
    pending = pending_account(cinema);
    if pending is None or pending.state != "testing" {
        raise Refused("nothing_to_test", "Connect M-Pesa first.");
    }
    return pending;
}

def _test(tenant: str, phone: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, OWNER);
    cinema = scope.tenant;
    account = _waiting(cinema);
    try {
        number = msisdn(phone);
    } except InvalidPhone as e {
        raise Refused("invalid_phone", str(e));
    }
    try {
        provider = account_provider(account);
    } except ProviderNotConfigured {
        raise Refused(
            "not_ready", "Connecting M-Pesa isn't available right now. Try again later."
        );
    }
    pushed = provider.stk_push(
        StkRequest(
            reference=f"TEST{account.version}{secrets.token_hex(3).upper()}",
            phone=number,
            amount_cents=TEST_CENTS,
            account="TEST",
            description="Test payment",
            # Nobody reads its callback: mpesa_test_status asks M-Pesa itself.
            callback_url=callback_url(secrets.token_urlsafe(24)),
            shortcode=pays_to(account)
        )
    );
    if not pushed.accepted {
        update_account(
            cinema, account, {"test_checkout_id": "", "test_text": pushed.message}
        );
        raise Refused(
            "test_not_sent",
            "M-Pesa didn't take the test payment: "
                + (pushed.message or "check the keys and the number.")
        );
    }
    update_account(
        cinema,
        account,
        {
            "test_checkout_id": pushed.checkout_request_id,
            "test_text": "Check the phone and enter the M-Pesa PIN to pay KES 1."
        }
    );
    return _settings(tenant);
}

def _test_status(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, OWNER);
    cinema = scope.tenant;
    account = _waiting(cinema);
    if not account.test_checkout_id {
        raise Refused("nothing_to_test", "Send the test payment first.");
    }
    try {
        asked = account_provider(account).query(account.test_checkout_id);
    } except ProviderNotConfigured {
        raise Refused(
            "not_ready", "Connecting M-Pesa isn't available right now. Try again later."
        );
    }
    if asked.state == PaymentState.SUCCESS and asked.amount_cents == TEST_CENTS {
        passed_test(cinema, account);
    } elif asked.state in [PaymentState.FAILED, PaymentState.CANCELLED] {
        update_account(
            cinema,
            account,
            {
                "test_checkout_id": "",
                "test_text": "The test payment didn't go through"
                    + (f": {asked.result_text}" if asked.result_text else ".")
            }
        );
    }
    return _settings(tenant);
}

def _cancel(tenant: str, sign_in: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, OWNER);
    cinema = scope.tenant;
    pending = pending_account(cinema);
    if pending is None {
        raise Refused("nothing_to_cancel", "There's no change waiting.");
    }
    who = verified_sign_in(sign_in) if sign_in else "";
    update_account(
        cinema,
        pending,
        {"state": "cancelled", "cancelled_at": now().isoformat(), "cancelled_by": who}
    );
    return _settings(tenant);
}

def:protect mpesa_settings(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _settings(tenant); });  # jac:ignore[W1037]
}

def:protect connect_mpesa(  # jac:ignore[W3030] the account's details, its keys and the password
    tenant: str,
    kind: str,
    shortcode: str,
    till_number: str,
    registered_name: str,
    keys: dict[str, str],
    password: str,
    sign_in: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "mpesa.connected",
        "mpesa_account",
        "",
        lambda -> any { return _connect(
            tenant,
            kind,
            shortcode,
            till_number,
            registered_name,
            keys,
            password,
            sign_in
        ); }  # jac:ignore[W1037]
    );
}

def:protect test_mpesa(tenant: str, phone: str) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "mpesa.test_sent",
        "mpesa_account",
        "",
        lambda -> any { return _test(tenant, phone); }  # jac:ignore[W1037]
    );
}

def:protect mpesa_test_status(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _test_status(tenant); });  # jac:ignore[W1037]
}

def:protect cancel_mpesa_change(tenant: str, sign_in: str) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "mpesa.cancelled",
        "mpesa_account",
        "",
        lambda -> any { return _cancel(tenant, sign_in); }  # jac:ignore[W1037]
    );
}
