"""P5.7: the Daraja adapter against Safaricom's real sandbox (opt-in; not in the suite).

Runs only when the sandbox settings are present (DARAJA_CONSUMER_KEY, DARAJA_CONSUMER_SECRET,
DARAJA_SHORTCODE, DARAJA_PASSKEY, DARAJA_CALLBACK_BASE and DARAJA_TEST_PHONE, the
phone that receives the prompt); otherwise each test says so and passes. Run it with
scripts/sandbox.sh, which loads .env; the nightly workflow runs it from repository
secrets.

It checks what the contract tests (tests/unit/daraja_tests.jac) can only assume: the
OAuth login works, Safaricom accepts our STK push (KES 1) and answers the status query
in a form the adapter understands. With DARAJA_RECORD=1 it writes Safaricom's real
responses, with tokens, passwords and phone numbers removed, to
tests/fixtures/daraja/recorded/ to replace the documented-format fixtures.

The full journey (a real payment producing a ticket) is manual: docs/runbooks/daraja-sandbox.md.
"""

import os;
import json;
import time;
import uuid;
import from pathlib { Path }
import from core.payments.state { PaymentState }
import from core.payments.provider { StkRequest }
import from core.payments.phone { msisdn }
import from core.payments.daraja {
    DarajaConfig,
    DarajaProvider,
    UrllibHttp,
    SANDBOX_URL
}

glob NEEDED: list[str] = [
         "DARAJA_CONSUMER_KEY",
         "DARAJA_CONSUMER_SECRET",
         "DARAJA_SHORTCODE",
         "DARAJA_PASSKEY",
         "DARAJA_CALLBACK_BASE",
         "DARAJA_TEST_PHONE"
     ],
     RECORDED: Path = Path(__file__).resolve().parent.parent
         / "tests"
         / "fixtures"
         / "daraja"
         / "recorded",
     HIDDEN: list[str] = [
         "access_token",
         "Password",
         "PhoneNumber",
         "PartyA",
         "MSISDN"
     ];

obj Reply {
    has kind: str,
        status: int,
        body: dict[str, any];  # jac:ignore[W1037]
}

obj RecordingHttp {
    # The real transport, keeping each reply so it can be saved as a fixture.
    has inner: UrllibHttp = UrllibHttp(),
        replies: list[Reply] = [];

    def send(
        method: str,
        url: str,
        headers: dict[str, str],
        body: dict[str, any] | None,  # jac:ignore[W1037]
        timeout: float
    ) -> tuple[int, dict[str, any]] {  # jac:ignore[W1037]
        (status, reply) = self.inner.send(method, url, headers, body, timeout);
        self.replies.append(
            Reply(kind=url.split("?")[0].rsplit("/", 1)[-1], status=status, body=reply)
        );
        return (status, reply);
    }
}

def _missing -> list[str] {
    return [
        n
        for n in NEEDED
        if not os.environ.get(n, "").strip()
    ];
}

def _redacted(value: any) -> any {  # jac:ignore[W1037]
    # A reply with secrets and phone numbers replaced.
    if isinstance(value, dict) {
        out: dict[str, any] = {};  # jac:ignore[W1037]
        for (k, v) in value.items() {
            out[k] = "REDACTED" if k in HIDDEN else _redacted(v);
        }
        return out;
    }
    if isinstance(value, list) {
        return [_redacted(v) for v in value];
    }
    return value;
}

def _record(http: RecordingHttp) {
    if os.environ.get("DARAJA_RECORD", "") != "1" {
        return;
    }
    RECORDED.mkdir(parents=True, exist_ok=True);
    for (i, r) in enumerate(http.replies) {
        (RECORDED / f"{i:02d}_{r.kind}_{r.status}.json").write_text(
            json.dumps(_redacted(r.body), indent=2) + "\n"
        );
    }
    print(f"recorded {len(http.replies)} replies to {RECORDED}");
}

test "sandbox: login, an STK push and its status query work against Safaricom" {
    missing = _missing();
    if missing {
        print(
            f"skipped: set {', '.join(missing)} (see docs/runbooks/daraja-sandbox.md)"
        );
        return;
    }
    http = RecordingHttp();
    daraja = DarajaProvider(
        config=DarajaConfig(
            consumer_key=os.environ["DARAJA_CONSUMER_KEY"].strip(),
            consumer_secret=os.environ["DARAJA_CONSUMER_SECRET"].strip(),
            shortcode=os.environ["DARAJA_SHORTCODE"].strip(),
            passkey=os.environ["DARAJA_PASSKEY"].strip(),
            base_url=os.environ.get("DARAJA_BASE_URL", "").strip() or SANDBOX_URL
        ),
        http=http
    );
    base = os.environ["DARAJA_CALLBACK_BASE"].strip().rstrip("/");
    pushed = daraja.stk_push(
        StkRequest(
            reference=f"SANDBOX{uuid.uuid4().hex[:5].upper()}",
            phone=msisdn(os.environ["DARAJA_TEST_PHONE"]),
            amount_cents=100,
            account="AFRICINEMAS",
            description="Sandbox test",
            callback_url=f"{base}/hooks/mpesa/sandbox-check-{uuid.uuid4().hex}"
        )
    );
    try {
        assert pushed.accepted , f"Safaricom refused the push: {pushed.error_code} {pushed.message}";
        assert pushed.checkout_request_id.startswith("ws_CO_") , pushed.checkout_request_id;
        # Give Safaricom a moment, then ask: processing, or already an answer.
        time.sleep(5);
        asked = daraja.query(pushed.checkout_request_id);
        assert asked.state
            in [
                PaymentState.STK_REQUESTED,
                PaymentState.SUCCESS,
                PaymentState.FAILED,
                PaymentState.CANCELLED
            ] , f"unexpected status: {asked.state} {asked.result_text}";
        print(
            f"sandbox push {pushed.checkout_request_id}: {asked.state.value} ({asked.result_text})"
        );
    } finally {
        _record(http);
    }
}
