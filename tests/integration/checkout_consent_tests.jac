"""P14.3c: paying is agreeing to the cinema's policies, and offers only when asked.

In-process app (payment_app.jac). Nova publishes its terms and refunds. Anna pays: the
order keeps the versions she was shown, and a later change of the terms doesn't change
it. Nova sends offers: Anna ticks the box as she pays, and her account at Nova finds
her subscribed; she stops them from My account. Without the tick nothing is recorded,
and a cinema that doesn't send offers records none.
"""

import from tests.support.served { Served }
import from tests.support.storefront_setup { code_of, browse, customer_at }
import uuid;
import from tests.support.payment_setup { paying_cinema, pay, fresh_phone, ANNA }

def _publish(app: Served, kind: str, text: str) {
    saved = app.call(
        "owner",
        "save_policy",
        {
            "tenant": "nova",
            "kind": kind,
            "text": text,
            "published": True,
            "reviewed": True
        }
    );
    assert saved["ok"] , saved;
}

def _sends_offers(app: Served, on: bool) {
    saved = app.call(
        "owner",
        "save_site_info",
        {"tenant": "nova", "info": {"business_name": "Nova Ltd", "sends_offers": on}}
    );
    assert saved["ok"] and saved["info"]["sends_offers"] == on , saved;
}

def _pay_with(app: Served, screening: str, email: str, offers: str) -> any {  # jac:ignore[W1037]
    # Anna's order, paid with `email`; offers "yes" when the box is ticked.
    return browse(
        app,
        "start_payment",
        {
            "slug": "nova",
            "screening_id": screening,
            "holder": ANNA,
            # Rejected at once (the simulator's number), so the order can be paid again.
            "phone": "254700000004",
            "email": email,
            "idempotency_key": f"pay-{uuid.uuid4().hex}",
            "adult": "yes",
            "offers": offers
        }
    );
}

test "the order keeps the policy versions shown when it was paid" {
    (app, nova, screening) = paying_cinema([]);
    try {
        _publish(app, "terms", "Ours.");
        _publish(app, "refunds", "Refunds.");
        started = pay(app, screening, fresh_phone());
        assert started["ok"] , started;
        shown = app.call(
            "owner", "pay_terms_shown", {"slug": "nova", "screening_id": screening}
        );
        assert len(shown) == 1
            and sorted(shown[0].keys()) == ["refunds", "terms"] , shown;
        first = shown[0]["terms"];
        assert first;
        _publish(app, "terms", "Ours, changed.");
        again = app.call(
            "owner", "pay_terms_shown", {"slug": "nova", "screening_id": screening}
        );
        assert again[0]["terms"] == first;
        # The cinema's branding says whether checkout offers the box.
        assert not browse(app, "public_branding", {"slug": "nova"})["info"][
            "sends_offers"
        ];
    } finally {
        app.close();
    }
}

test "offers are recorded only when ticked, and stop from My account" {
    (app, nova, screening) = paying_cinema([]);
    try {
        # Ticked, at a cinema that doesn't send offers: nothing.
        first = _pay_with(app, screening, "anna@example.com", "yes");
        assert first["ok"] , first;
        customer_at(app, "nova", "anna", "anna@example.com");
        assert app.call("anna", "my_offers", {"slug": "nova"})
            == {"ok": True, "sends_offers": False, "subscribed": False};
        assert code_of(
            app.call(
                "anna",
                "set_my_offers",
                {"slug": "nova", "subscribed": True, "source": ""}
            )
        )
            == "no_offers";
        _sends_offers(app, True);
        assert browse(app, "public_branding", {"slug": "nova"})["info"]["sends_offers"];
        # Not ticked: nothing; ticked: recorded for the email that paid.
        assert _pay_with(app, screening, "bo@example.com", "")["ok"];
        customer_at(app, "nova", "bo", "bo@example.com");
        assert not app.call("bo", "my_offers", {"slug": "nova"})["subscribed"];
        assert _pay_with(app, screening, "anna@example.com", "yes")["ok"];
        mine = app.call("anna", "my_offers", {"slug": "nova"});
        assert mine["sends_offers"] and mine["subscribed"] , mine;
        kept = app.call(
            "owner", "pay_offer_consent", {"slug": "nova", "email": "ANNA@example.com"}
        );
        assert kept["source"] == "checkout" and kept["reference"] and kept["given_at"];
        stopped = app.call(
            "anna", "set_my_offers", {"slug": "nova", "subscribed": False, "source": ""}
        );
        assert stopped["ok"] and not stopped["subscribed"] , stopped;
        # Withdrawn, the record stays as the proof.
        assert app.call(
            "owner", "pay_offer_consent", {"slug": "nova", "email": "anna@example.com"}
        )["withdrawn_at"];
        again = app.call(
            "bo",
            "set_my_offers",
            {"slug": "nova", "subscribed": True, "source": "signup"}
        );
        assert again["subscribed"];
        # Only a customer of the cinema has offers to read.
        assert code_of(app.call("owner", "my_offers", {"slug": "nova"}))
            == "not_your_cinema";
    } finally {
        app.close();
    }
}

test "paying online needs the customer's word that they're 18 or over" {
    (app, nova, screening) = paying_cinema([]);
    try {
        body = {
            "slug": "nova",
            "screening_id": screening,
            "holder": ANNA,
            "phone": "254700000004",
            "email": "anna@example.com",
            "idempotency_key": f"pay-{uuid.uuid4().hex}"
        };
        # Left out, or anything but "yes": refused (P15.0).
        for given in [{}, {"adult": ""}, {"adult": "no"}, {"adult": "True"}] {
            got = browse(app, "start_payment", {** body, ** given});
            assert code_of(got) == "adult_required" , (given, got);
            assert "18 or over" in got["error"]["message"];
        }
        assert browse(app, "start_payment", {** body, "adult": "yes"})["ok"];
    } finally {
        app.close();
    }
}
