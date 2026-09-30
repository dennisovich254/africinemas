"""P3.8a: a cinema's branding, through the production app (main.jac).

The theme is edited as a draft (save_theme, upload_logo, remove_logo) and goes public
only when published: each publish is a new, numbered version, and rolling back publishes
an earlier version's theme and logo again as the next version. The published theme and
logo are projected to the cinema's storefront, where public_branding(slug) serves them
with their CSS, to anyone. Unreadable colours are repaired on save, and the changes are
reported. Branding needs tenant.settings.update; another cinema's is never touched.
"""

import io;
import base64;
import from os { path }
import from PIL { Image }
import from core.theming.tokens { DEFAULT_THEME }
import from tests.support.served { Served, served }

glob MAIN: str = path.join(
         path.dirname(path.dirname(path.dirname(path.abspath(__file__)))), "main.jac"
     ),
     NOVA: str = "nova";

def _cinema(names: list[str]) -> Served {
    app = served(MAIN, ["owner"] + names);
    app.call("owner", "create_cinema", {"name": "Nova Cinemas", "slug": NOVA});
    app.call("owner", "start_shift", {"tenant": NOVA});
    return app;
}

def _theme(accent: str = "#E0A526", name: str = "Nova Gold") -> dict[str, any] {  # jac:ignore[W1037]
    data: dict[str, any] = DEFAULT_THEME.as_dict();  # jac:ignore[W1037]
    light = dict(data["light"]);
    light["accent"] = accent;
    data["light"] = light;
    data["name"] = name;
    return data;
}

def _save(app: Served, theme: dict[str, any], who: str = "owner") -> any {  # jac:ignore[W1037]
    return app.call(who, "save_theme", {"tenant": NOVA, "theme": theme});
}

def _branding(app: Served, who: str = "owner") -> any {  # jac:ignore[W1037]
    return app.call(who, "get_branding", {"tenant": NOVA});
}

def _public(app: Served, slug: str = NOVA) -> any {  # jac:ignore[W1037]
    # The storefront's branding, as an anonymous visitor sees it.
    app.client.set_auth_token("");
    resp = app.client.post("/function/public_branding", json={"slug": slug});
    assert resp.status_code == 200 , resp.text;
    return resp.data["result"];
}

def _png(size: tuple[int, int] = (300, 120)) -> str {
    out = io.BytesIO();
    Image.new("RGBA", size, (231, 176, 58, 255)).save(out, format="PNG");
    return base64.b64encode(out.getvalue()).decode();
}

def _code(answer: dict[str, any]) -> str {  # jac:ignore[W1037]
    return "" if answer["ok"] else answer["error"]["code"];
}

test "a new cinema starts from the default theme, with the presets to choose from" {
    app = _cinema([]);
    try {
        answer = _branding(app);
        assert answer["ok"] , answer;
        b = answer["branding"];
        assert b["draft"]["theme"] == DEFAULT_THEME.as_dict();
        assert b["draft"]["has_logo"] is False;
        assert b["published"] is None and b["versions"] == [];
        assert [p["name"] for p in answer["presets"]]
            == ["AfriCinemas", "Projector Black", "Velvet Curtain", "Blackout Crimson"];
        public = _public(app);
        assert public["ok"] and public["branding"]["version"] == 0 , public;
        assert public["branding"]["theme"] == DEFAULT_THEME.as_dict();
        assert public["branding"]["logo"] == "";
    } finally {
        app.close();
    }
}

test "a saved draft stays private until it is published as a new version" {
    app = _cinema([]);
    try {
        saved = _save(app, _theme("#D97706"));
        assert saved["ok"] and saved["adjusted"] == [] , saved;
        assert saved["theme"]["light"]["accent"] == "#D97706";
        assert _branding(app)["branding"]["draft"]["theme"]["light"]["accent"]
            == "#D97706";
        assert _public(app)["branding"]["version"] == 0 , "a draft isn't public";
        first = app.call("owner", "publish_theme", {"tenant": NOVA});
        assert first["ok"] and first["version"] == 1 , first;
        public = _public(app)["branding"];
        assert public["version"] == 1 and public["theme"]["name"] == "Nova Gold";
        assert "--primary: #D97706;" in public["css"] , public["css"];
        assert '[data-surface="storefront"]' in public["css"];
        _save(app, _theme("#B45309", name="Nova Amber"));
        assert app.call("owner", "publish_theme", {"tenant": NOVA})["version"] == 2;
        app.restart();
        b = _branding(app)["branding"];
        assert b["published"]["version"] == 2
            and b["published"]["theme"]["name"] == "Nova Amber";
        assert [(v["version"], v["name"]) for v in b["versions"]]
            == [(2, "Nova Amber"), (1, "Nova Gold")];
        assert _public(app)["branding"]["version"] == 2;
    } finally {
        app.close();
    }
}

test "publishing needs a change, and rolling back republishes an earlier version" {
    app = _cinema([]);
    try {
        nothing = app.call("owner", "publish_theme", {"tenant": NOVA});
        assert _code(nothing) == "nothing_to_publish" , nothing;
        _save(app, _theme("#D97706", name="One"));
        app.call("owner", "publish_theme", {"tenant": NOVA});
        again = app.call("owner", "publish_theme", {"tenant": NOVA});
        assert _code(again) == "nothing_to_publish" , again;
        _save(app, _theme("#B45309", name="Two"));
        app.call("owner", "publish_theme", {"tenant": NOVA});
        back = app.call("owner", "rollback_theme", {"tenant": NOVA, "version": 1});
        assert back["ok"] and back["version"] == 3 , back;
        public = _public(app)["branding"];
        assert public["version"] == 3 and public["theme"]["name"] == "One";
        assert public["theme"]["light"]["accent"] == "#D97706";
        b = _branding(app)["branding"];
        assert b["draft"]["theme"]["name"] == "One" , "the draft follows a rollback";
        assert [v["version"] for v in b["versions"]] == [3, 2, 1];
        missing = app.call("owner", "rollback_theme", {"tenant": NOVA, "version": 9});
        assert _code(missing) == "unknown_version" , missing;
    } finally {
        app.close();
    }
}

test "unreadable colours are repaired on save, and each change is reported" {
    app = _cinema([]);
    try {
        theme = _theme();
        light = dict(theme["light"]);
        light["link"] = "#F5F2EA";  # nearly the page colour
        theme["light"] = light;
        saved = _save(app, theme);
        assert saved["ok"] , saved;
        assert [(a["mode"], a["role"], a["before"]) for a in saved["adjusted"]]
            == [("light", "link", "#F5F2EA")] , saved["adjusted"];
        stored = _branding(app)["branding"]["draft"]["theme"]["light"]["link"];
        assert stored == saved["adjusted"][0]["after"] != "#F5F2EA";
    } finally {
        app.close();
    }
}

test "anything but token values is refused, and nothing is stored" {
    app = _cinema([]);
    try {
        injected = _theme();
        light = dict(injected["light"]);
        light["accent"] = "#E0A526;}body{display:none";
        injected["light"] = light;
        font = _theme();
        font["display_font"] = "Comic Sans";
        extra = _theme();
        extra["css"] = "body{}";
        for bad in [injected, font, extra] {
            answer = _save(app, bad);
            assert _code(answer) == "invalid_theme" , answer;
        }
        assert _branding(app)["branding"]["draft"]["theme"] == DEFAULT_THEME.as_dict();
    } finally {
        app.close();
    }
}

test "a logo is part of the draft, and published and rolled back with the theme" {
    app = _cinema([]);
    try {
        up = app.call(
            "owner",
            "upload_logo",
            {"tenant": NOVA, "content_type": "image/png", "data_base64": _png()}
        );
        assert up["ok"] , up;
        assert _branding(app)["branding"]["draft"]["has_logo"];
        assert _public(app)["branding"]["logo"] == "" , "a draft logo isn't public";
        app.call("owner", "publish_theme", {"tenant": NOVA});
        logo = _public(app)["branding"]["logo"];
        assert logo.startswith("data:image/webp;base64,") , logo[:40];
        webp = Image.open(io.BytesIO(base64.b64decode(logo.split(",", 1)[1])));
        assert webp.format == "WEBP" and webp.size == (300, 120);
        assert app.call("owner", "remove_logo", {"tenant": NOVA})["ok"];
        assert app.call("owner", "publish_theme", {"tenant": NOVA})["version"] == 2;
        assert _public(app)["branding"]["logo"] == "";
        app.call("owner", "rollback_theme", {"tenant": NOVA, "version": 1});
        assert _public(app)["branding"]["logo"] == logo , "the logo comes back too";
        bad = app.call(
            "owner",
            "upload_logo",
            {"tenant": NOVA, "content_type": "image/png", "data_base64": _png((20, 20))}
        );
        assert _code(bad) == "too_small" , bad;
    } finally {
        app.close();
    }
}

test "only staff who manage the cinema's settings can change its branding" {
    # Not "admin": that name is Jac's own development admin account.
    app = _cinema(["bo", "manager"]);
    try {
        for (who, role) in [("bo", "box_office_agent"), ("manager", "tenant_admin")] {
            token = app.call(
                "owner", "invite_staff", {"tenant": NOVA, "role": role, "venue_id": ""}
            )["token"];
            app.call(who, "accept_invite", {"token": token});
            app.call(who, "start_shift", {"tenant": NOVA});
        }
        assert _code(_branding(app, "bo")) == "forbidden";
        assert _code(_save(app, _theme(), "bo")) == "forbidden";
        assert _code(app.call("bo", "publish_theme", {"tenant": NOVA})) == "forbidden";
        assert _save(app, _theme("#D97706"), "manager")["ok"];
        assert app.call("manager", "publish_theme", {"tenant": NOVA})["version"] == 1;
        app.call("owner", "end_shift", {"tenant": NOVA});
        assert _code(_branding(app)) == "no_shift";
    } finally {
        app.close();
    }
}

test "one cinema's branding never changes another's" {
    app = _cinema(["rival"]);
    try {
        app.call("rival", "create_cinema", {"name": "Rift", "slug": "rift"});
        app.call("rival", "start_shift", {"tenant": "rift"});
        _save(app, _theme("#D97706"));
        app.call("owner", "publish_theme", {"tenant": NOVA});
        rift = _public(app, "rift")["branding"];
        assert rift["version"] == 0 and rift["theme"] == DEFAULT_THEME.as_dict();
        assert _code(app.call("rival", "get_branding", {"tenant": NOVA}))
            == "not_found";
        assert _code(app.call("rival", "publish_theme", {"tenant": NOVA}))
            == "not_found";
        assert _code(_public(app, "no-such-cinema")) == "not_found";
    } finally {
        app.close();
    }
}
