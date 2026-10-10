"""ADR-0007: atomic unique claims (in-process app). Concurrency: see
tenant_slug_concurrency_tests.jac, which races real requests on a real server.
"""

import time;
import from os { path }
import from tests.support.served { served }

glob APP: str = path.join(
         path.dirname(path.dirname(path.abspath(__file__))), "apps", "claims_app.jac"
     );

test "the first owner wins, a repeat is idempotent, and others are told the holder" {
    app = served(APP, ["u"]);
    try {
        c = lambda (owner: str) -> str { return app.call(
            "u", "c_claim", {"ns": "slug", "key": "nova", "owner": owner, "ttl": 0}
        ); };
        assert c("t-a") == "t-a";
        assert c("t-a") == "t-a";
        assert c("t-b") == "t-a";
        assert app.call("u", "c_holder", {"ns": "slug", "key": "nova"}) == "t-a";
        assert app.call("u", "c_holder", {"ns": "slug", "key": "other"}) is None;
    } finally {
        app.close();
    }
}

test "namespaces keep the same key apart" {
    app = served(APP, ["u"]);
    try {
        app.call(
            "u", "c_claim", {"ns": "slug", "key": "nova", "owner": "t-a", "ttl": 0}
        );
        assert app.call(
            "u", "c_claim", {"ns": "seat", "key": "nova", "owner": "t-b", "ttl": 0}
        )
            == "t-b";
    } finally {
        app.close();
    }
}

test "a provisional claim expires and can then be taken over" {
    app = served(APP, ["u"]);
    try {
        assert app.call(
            "u", "c_claim", {"ns": "slug", "key": "nova", "owner": "t-a", "ttl": 1}
        )
            == "t-a";
        assert app.call(
            "u", "c_claim", {"ns": "slug", "key": "nova", "owner": "t-b", "ttl": 0}
        )
            == "t-a";
        time.sleep(1.5);
        assert app.call("u", "c_holder", {"ns": "slug", "key": "nova"}) is None;
        assert app.call(
            "u", "c_claim", {"ns": "slug", "key": "nova", "owner": "t-b", "ttl": 0}
        )
            == "t-b";
    } finally {
        app.close();
    }
}

test "only the holder can make a claim permanent, and then it never expires" {
    app = served(APP, ["u"]);
    try {
        app.call(
            "u", "c_claim", {"ns": "slug", "key": "nova", "owner": "t-a", "ttl": 1}
        );
        assert not app.call(
            "u", "c_permanent", {"ns": "slug", "key": "nova", "owner": "t-b"}
        );
        assert app.call(
            "u", "c_permanent", {"ns": "slug", "key": "nova", "owner": "t-a"}
        );
        time.sleep(1.5);
        assert app.call("u", "c_holder", {"ns": "slug", "key": "nova"}) == "t-a";
    } finally {
        app.close();
    }
}

test "only the holder can release a claim" {
    app = served(APP, ["u"]);
    try {
        app.call(
            "u", "c_claim", {"ns": "slug", "key": "nova", "owner": "t-a", "ttl": 0}
        );
        assert not app.call(
            "u", "c_release", {"ns": "slug", "key": "nova", "owner": "t-b"}
        );
        assert app.call(
            "u", "c_release", {"ns": "slug", "key": "nova", "owner": "t-a"}
        );
        assert app.call("u", "c_holder", {"ns": "slug", "key": "nova"}) is None;
    } finally {
        app.close();
    }
}

test "take_claim hands a live claim's value to exactly one caller, never an expired one" {
    # Single-use secrets (OAuth codes and refresh tokens, P8.6a): taking deletes.
    app = served(APP, ["u"]);
    try {
        t = lambda (key: str) -> any { return app.call(
            "u", "c_take", {"ns": "code", "key": key}
        ); };  # jac:ignore[W1037]
        app.call("u", "c_claim", {"ns": "code", "key": "k1", "owner": "v1", "ttl": 60});
        assert t("k1") == "v1";
        assert t("k1") is None;
        assert t("never-made") is None;
        app.call("u", "c_claim", {"ns": "code", "key": "k2", "owner": "v2", "ttl": 1});
        time.sleep(1.5);
        assert t("k2") is None;
    } finally {
        app.close();
    }
}
