"""P15.3: each cinema's M-Pesa keys and settings (ADR-0082).

- Keys are sealed with AES-GCM and open only for the cinema, version and field they
  were sealed for, and only with the server's secret; without it nothing is sealed.
- A Till pushes to its till number, signed with its store number; a Paybill to itself.
- The registered name matches however "Limited" and capitals are written.
- Against live Daraja every cinema must use its own M-Pesa.
- The setup video plays from youtube-nocookie.com for a YouTube link, else is a link.
"""

import os;
import json;
import from core.payments.secret_box {
    seal,
    open_sealed,
    sealing_ready,
    SealingKeyMissing,
    CannotOpen
}
import from core.payments.mpesa_account { MpesaAccount, config_of, account_view }
import from core.payments.mpesa_api { same_name }
import from core.payments.choice { own_account_required }
import from core.payments.provider { StkRequest }
import from core.payments.daraja { DarajaProvider }
import from core.payments.setup_help { embed_of }

glob ENV: str = "AFRICINEMAS_MPESA_KEY",
     SECRET: str = "unit-test-sealing-secret-0123456789abcdef";

def _with_secret(value: str | None) -> str | None {
    before = os.environ.pop(ENV, None);
    if value is not None {
        os.environ[ENV] = value;
    }
    return before;
}

def _restore(before: str | None) {
    os.environ.pop(ENV, None);
    if before is not None {
        os.environ[ENV] = before;
    }
}

test "sealed keys open only for what they were sealed for, with the same secret" {
    before = _with_secret(SECRET);
    try {
        token = seal("the-passkey", "mpesa|t1|1|passkey");
        assert token.startswith("v1.") and "the-passkey" not in token;
        assert open_sealed(token, "mpesa|t1|1|passkey") == "the-passkey";
        # A fresh nonce each time: the same key never seals the same way twice.
        assert seal("the-passkey", "mpesa|t1|1|passkey") != token;
        for other in [
            "mpesa|t2|1|passkey",
            "mpesa|t1|2|passkey",
            "mpesa|t1|1|consumer_key"
        ] {
            try {
                open_sealed(token, other);
                assert False , other;
            } except CannotOpen {}
        }
        changed = token[:-4] + ("AAAA" if not token.endswith("AAAA") else "BBBB");
        try {
            open_sealed(changed, "mpesa|t1|1|passkey");
            assert False;
        } except CannotOpen {}
        _with_secret("another-secret-of-thirty-two-characters!");
        try {
            open_sealed(token, "mpesa|t1|1|passkey");
            assert False;
        } except CannotOpen {}
    } finally {
        _restore(before);
    }
}

test "without the server's secret nothing is sealed" {
    for value in [None, "too-short"] {
        before = _with_secret(value);
        try {
            assert not sealing_ready();
            try {
                seal("x", "c");
                assert False;
            } except SealingKeyMissing {}
        } finally {
            _restore(before);
        }
    }
}

def _account(kind: str, shortcode: str, till: str) -> MpesaAccount {
    sealed = {
        field: seal(f"{field}-value", f"mpesa|t1|3|{field}")
        for field in ["consumer_key", "consumer_secret", "passkey"]
    };
    return MpesaAccount(
        tenant_id="t1",
        version=3,
        kind=kind,
        shortcode=shortcode,
        till_number=till,
        registered_name="Kim's Cinema Ltd",
        sealed=sealed,
        key_hint="ABCD"
    );
}

test "a till is signed with its store number and paid to its till; a paybill to itself" {
    before = _with_secret(SECRET);
    try {
        till = config_of(_account("till", "700200", "800300"), "https://example.test");
        assert till.shortcode == "700200" and till.party_b == "800300";
        assert till.transaction_type == "CustomerBuyGoodsOnline";
        assert till.passkey == "passkey-value"
            and till.consumer_secret == "consumer_secret-value";
        paybill = config_of(_account("paybill", "600100", ""), "https://example.test");
        assert paybill.party_b == ""
            and paybill.transaction_type == "CustomerPayBillOnline";
        # The view never carries a key.
        view = json.dumps(account_view(_account("till", "700200", "800300")));
        assert "value" not in view and "v1." not in view and "ABCD" in view;
        assert "800300" in view;
    } finally {
        _restore(before);
    }
}

obj Recorder {
    has sent: list[dict[str, any]] = [];  # jac:ignore[W1037]

    def send(
        _method: str,
        url: str,
        _headers: dict[str, str],
        body: dict[str, any] | None,  # jac:ignore[W1037]
        _timeout: float
    ) -> tuple[int, dict[str, any]] {  # jac:ignore[W1037]
        self.sent.append(body or {});
        if url.endswith("/oauth/v1/generate?grant_type=client_credentials") {
            return (200, {"access_token": "tok", "expires_in": "3599"});
        }
        return (
            200,
            {
                "MerchantRequestID": "m1",
                "CheckoutRequestID": "ws_CO_1",
                "ResponseCode": "0",
                "ResponseDescription": "Success. Request accepted for processing"
            }
        );
    }
}

test "a till's push names the store number and sends the money to the till" {
    before = _with_secret(SECRET);
    try {
        http = Recorder();
        provider = DarajaProvider(
            config=config_of(
                _account("till", "700200", "800300"), "https://example.test"
            ),
            http=http
        );
        pushed = provider.stk_push(
            StkRequest(
                reference="R1",
                phone="254712345678",
                amount_cents=100,
                account="TEST",
                description="Test payment",
                callback_url="https://pay.example.org/hooks/mpesa/x"
            )
        );
        assert pushed.accepted , pushed.message;
        body = http.sent[-1];
        assert body["BusinessShortCode"] == "700200" and body["PartyB"] == "800300";
        assert body["TransactionType"] == "CustomerBuyGoodsOnline";
    } finally {
        _restore(before);
    }
}

test "the registered name matches however Limited and capitals are written" {
    assert same_name("KIM'S CINEMA LIMITED", "Kim's Cinema Ltd");
    assert same_name("Kims  Cinema Ltd.", "Kim's Cinema Ltd");
    assert same_name("Rupa Mall Cinemas & Co", "rupa mall cinemas and company");
    assert not same_name("Kim's Cinema Ltd", "Kim's Cinemas Ltd");
    assert not same_name("", "");
}

test "against live Daraja every cinema must use its own M-Pesa" {
    keep = {
        name: os.environ.get(name)
        for name in ["AFRICINEMAS_PAYMENTS", "DARAJA_BASE_URL", "AFRICINEMAS_OWN_MPESA"]
    };
    try {
        for name in keep {
            os.environ.pop(name, None);
        }
        os.environ["AFRICINEMAS_PAYMENTS"] = "simulator";
        assert not own_account_required();
        os.environ["AFRICINEMAS_OWN_MPESA"] = "required";
        assert own_account_required();
        os.environ.pop("AFRICINEMAS_OWN_MPESA");
        os.environ["AFRICINEMAS_PAYMENTS"] = "daraja";
        assert not own_account_required();
        os.environ["DARAJA_BASE_URL"] = "https://api.safaricom.co.ke";
        assert own_account_required();
    } finally {
        for (name, value) in keep.items() {
            os.environ.pop(name, None);
            if value is not None {
                os.environ[name] = value;
            }
        }
    }
}

test "a YouTube link plays from youtube-nocookie; anything else is only a link" {
    player = "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ";
    for link in [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://youtu.be/dQw4w9WgXcQ",
        "https://m.youtube.com/watch?v=dQw4w9WgXcQ&t=30",
        "https://www.youtube.com/embed/dQw4w9WgXcQ"
    ] {
        assert embed_of(link) == player , link;
    }
    for other in [
        "https://vimeo.com/123456",
        "https://www.youtube.com/watch?v=bad\"id",
        "https://evil.example/youtube.com/watch?v=dQw4w9WgXcQ"
    ] {
        assert embed_of(other) == "" , other;
    }
}
