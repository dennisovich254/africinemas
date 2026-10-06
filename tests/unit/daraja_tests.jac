"""P5.2: the Daraja adapter (core/payments/daraja.jac), against recorded-format responses.

No network: a fake transport replays the bodies in tests/fixtures/daraja/ and records
what the adapter sent, so these are contract tests of both directions. They cover the
OAuth token (fetched once, reused, refreshed when it expires or is refused), the STK
push (Safaricom's exact fields), the status query, the callback body, timeouts and
retries (reads are retried; a push never is, since that could prompt twice), and that
no secret reaches the logs.
"""

import json;
import base64;
import logging;
import from pathlib { Path }
import from datetime { datetime, timedelta, timezone }
import from core.payments.state { PaymentState }
import from core.payments.provider { StkRequest }
import from core.payments.daraja {
    DarajaConfig,
    DarajaProvider,
    parse_callback,
    stk_password,
    daraja_timestamp
}

glob FIXTURES: Path = Path(__file__).resolve().parent.parent
         / "fixtures"
         / "daraja",
     KEY: str = "consumer-KEY-8f3b2a",
     SECRET: str = "consumer-SECRET-77d1e9",
     PASSKEY: str = "bfb279f9aa9bdbcf158e97dd71a467cd2e0c893059b10f78e6b72ada1ed2c919",
     # 2026-10-06 12:00 in Nairobi (UTC+3).
     START: datetime = datetime(2026, 10, 6, 9, 0, tzinfo=timezone.utc),
     CALLBACK: str = "https://pay.example.org/hooks/mpesa/tok-0123456789abcdef";

def _body(name: str) -> dict[str, any] {  # jac:ignore[W1037]
    return json.loads((FIXTURES / f"{name}.json").read_text());
}

obj FakeHttp {
    # Replays (status, fixture) replies in order; "timeout" raises TimeoutError.
    has replies: list[any] = [],  # jac:ignore[W1037]
        calls: list[dict[str, any]] = [];  # jac:ignore[W1037]

    def send(
        method: str,
        url: str,
        headers: dict[str, str],
        body: dict[str, any] | None,  # jac:ignore[W1037]
        _timeout: float
    ) -> tuple[int, dict[str, any]] {  # jac:ignore[W1037]
        self.calls.append(
            {"method": method, "url": url, "headers": headers, "body": body}
        );
        reply = self.replies.pop(0);
        if reply == "timeout" {
            raise TimeoutError("timed out");
        }
        return (reply[0], _body(reply[1]));
    }
}

obj FakeClock {
    has at: datetime = START;

    def now -> datetime {
        return self.at;
    }
}

def _provider(http: FakeHttp, clock: FakeClock | None = None) -> DarajaProvider {
    return DarajaProvider(
        config=DarajaConfig(
            base_url="https://sandbox.safaricom.co.ke",
            consumer_key=KEY,
            consumer_secret=SECRET,
            shortcode="174379",
            passkey=PASSKEY
        ),
        http=http,
        clock=clock or FakeClock(),
        backoff_s=0.0
    );
}

def _request(reference: str = "ord-1", cents: int = 156000) -> StkRequest {
    return StkRequest(
        reference=reference,
        phone="254712345678",
        amount_cents=cents,
        account="NOVA-CINEMAS-WESTGATE",
        description="Tickets for Rafiki tonight",
        callback_url=CALLBACK
    );
}

test "the STK password and timestamp are Safaricom's, in Nairobi time" {
    assert daraja_timestamp(START) == "20261006120000";
    expected = base64.b64encode(f"174379{PASSKEY}20261006120000".encode()).decode();
    assert stk_password("174379", PASSKEY, "20261006120000") == expected;
}

test "a push logs in once, then sends Safaricom's exact fields" {
    http = FakeHttp(replies=[(200, "oauth_ok"), (200, "stk_push_ok")]);
    pushed = _provider(http).stk_push(_request());
    assert pushed.accepted and pushed.checkout_request_id == "ws_CO_191220191020363925";
    login = http.calls[0];
    assert login["method"] == "GET"
        and login["url"].endswith("/oauth/v1/generate?grant_type=client_credentials");
    assert login["headers"]["Authorization"]
        == "Basic " + base64.b64encode(f"{KEY}:{SECRET}".encode()).decode();
    push = http.calls[1];
    assert push["url"].endswith("/mpesa/stkpush/v1/processrequest");
    assert push["headers"]["Authorization"]
        == "Bearer TOKEN-ONE-c9SQxWWhmdVRlyh0zh8gZDTkubVF";
    sent = push["body"];
    assert sent["BusinessShortCode"] == "174379" and sent["PartyB"] == "174379";
    assert sent["Timestamp"] == "20261006120000";
    assert sent["Password"] == stk_password("174379", PASSKEY, "20261006120000");
    assert sent["TransactionType"] == "CustomerPayBillOnline";
    assert sent["Amount"] == 1560 and isinstance(sent["Amount"], int);
    assert sent["PartyA"] == "254712345678" and sent["PhoneNumber"] == "254712345678";
    assert sent["CallBackURL"] == CALLBACK;
    assert len(sent["AccountReference"]) <= 12 and len(sent["TransactionDesc"]) <= 13;
}

test "the token is reused until it nearly expires, and refreshed when refused" {
    clock = FakeClock();
    http = FakeHttp(
        replies=[
            (200, "oauth_ok"),
            (200, "stk_push_ok"),
            (200, "stk_query_success"),
            (200, "oauth_second"),
            (200, "stk_query_success"),
            (401, "token_invalid"),
            (200, "oauth_ok"),
            (200, "stk_query_success")
        ]
    );
    daraja = _provider(http, clock);
    daraja.stk_push(_request());
    daraja.query("ws_CO_191220191020363925");
    assert len(
        [
            c
            for c in http.calls
            if "oauth" in c["url"]
        ]
    )
        == 1;
    # Just under an hour later the token is about to expire: a new one is fetched.
    clock.at = START + timedelta(seconds=3560);
    daraja.query("ws_CO_191220191020363925");
    assert http.calls[-1]["headers"]["Authorization"]
        == "Bearer TOKEN-TWO-0Rxa3zN8hBqkF6wYtLp2";
    # Safaricom refuses a token early: log in again and repeat the call once.
    asked = daraja.query("ws_CO_191220191020363925");
    assert asked.state == PaymentState.SUCCESS;
    assert len(
        [
            c
            for c in http.calls
            if "oauth" in c["url"]
        ]
    )
        == 3;
}

test "a refused push says why, and a push that times out is uncertain, never retried" {
    refused = _provider(
        FakeHttp(replies=[(200, "oauth_ok"), (500, "stk_push_error")])
    ).stk_push(
        _request()
    );
    assert not refused.accepted and refused.error_code == "500.001.1001";
    assert not refused.uncertain;
    http = FakeHttp(replies=[(200, "oauth_ok"), "timeout"]);
    timed_out = _provider(http).stk_push(_request());
    assert not timed_out.accepted and timed_out.uncertain;
    assert timed_out.error_code == "timeout";
    assert len(
        [
            c
            for c in http.calls
            if "stkpush" in c["url"]
        ]
    )
        == 1;
}

test "a push for an amount or number M-Pesa can't take is never sent" {
    http = FakeHttp(replies=[]);
    bad = _provider(http).stk_push(_request(cents=156050));
    assert not bad.accepted and bad.error_code == "invalid_request";
    no_callback = _request();
    no_callback.callback_url = "http://insecure.example.org/hook";
    assert _provider(http).stk_push(no_callback).error_code == "invalid_request";
    assert http.calls == [];
}

test "a status query maps paid, cancelled, still waiting and unknown" {
    for (fixture, status, state) in [
        ("stk_query_success", 200, PaymentState.SUCCESS),
        ("stk_query_cancelled", 200, PaymentState.CANCELLED),
        ("stk_query_processing", 500, PaymentState.STK_REQUESTED),
        ("stk_query_unknown", 400, PaymentState.UNKNOWN)
    ] {
        http = FakeHttp(replies=[(200, "oauth_ok"), (status, fixture)]);
        asked = _provider(http).query("ws_CO_191220191020363925");
        assert asked.state == state , (fixture, asked.state);
        sent = http.calls[1]["body"];
        assert sent["CheckoutRequestID"] == "ws_CO_191220191020363925";
        assert sent["Password"] == stk_password("174379", PASSKEY, "20261006120000");
    }
}

test "a query that times out is retried, and says unknown if it never answers" {
    http = FakeHttp(replies=[(200, "oauth_ok"), "timeout", (200, "stk_query_success")]);
    assert _provider(http).query("ws_CO_1").state == PaymentState.SUCCESS;
    never = FakeHttp(replies=[(200, "oauth_ok"), "timeout", "timeout", "timeout"]);
    asked = _provider(never).query("ws_CO_1");
    assert asked.state == PaymentState.UNKNOWN;
    assert len(
        [
            c
            for c in never.calls
            if "stkpushquery" in c["url"]
        ]
    )
        == 3;
}

test "a callback body becomes a status: paid with its receipt, or cancelled" {
    paid = parse_callback(_body("callback_success"));
    assert paid is not None;
    assert paid.state == PaymentState.SUCCESS and paid.result_code == 0;
    assert paid.checkout_request_id == "ws_CO_191220191020363925";
    assert paid.receipt == "NLJ7RT61SV" and paid.amount_cents == 156000;
    assert paid.phone == "254712345678";
    cancelled = parse_callback(_body("callback_cancelled"));
    assert cancelled is not None and cancelled.state == PaymentState.CANCELLED;
    assert not cancelled.receipt;
    for junk in [{}, {"Body": {}}, {"Body": {"stkCallback": {"ResultCode": 0}}}] {
        assert parse_callback(junk) is None , junk;
    }
}

test "no secret reaches the logs or the config's printed form" {
    seen: list[str] = [];
    handler = logging.Handler();
    handler.emit = lambda (record: any) { seen.append(record.getMessage()); };  # jac:ignore[W1037]
    logger = logging.getLogger("africinemas.payments");
    logger.addHandler(handler);
    logger.setLevel(logging.DEBUG);
    try {
        http = FakeHttp(
            replies=[
                (200, "oauth_ok"),
                (200, "stk_push_ok"),
                (500, "stk_push_error"),
                (401, "token_invalid"),
                (200, "oauth_ok"),
                (200, "stk_query_success")
            ]
        );
        daraja = _provider(http);
        daraja.stk_push(_request());
        daraja.stk_push(_request("ord-2"));
        daraja.query("ws_CO_191220191020363925");
    } finally {
        logger.removeHandler(handler);
    }
    text = "\n".join(seen) + "\n" + repr(daraja.config) + str(daraja.config);
    assert seen , "the adapter should log what it does";
    for secret in [
        KEY,
        SECRET,
        PASSKEY,
        "TOKEN-ONE",
        stk_password("174379", PASSKEY, "20261006120000"),
        "254712345678"
    ] {
        assert secret not in text , secret;
    }
}
