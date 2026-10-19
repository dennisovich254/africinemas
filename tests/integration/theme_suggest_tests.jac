"""Theme suggestions from the logo, through the endpoint (ADR-0043, suggest_themes).

In-process app (payment_app.jac) with a scripted model (script_theme_model, MockLLM).
- It needs the draft logo, and tenant.settings.update like the rest of branding.
- The theme it returns (one per ask) is readable; nothing is saved until the owner picks one.
- A failing model still answers, with one theme built from the logo.
- SUGGEST_DAILY (5) a day per cinema: the sixth is refused.
"""

import io;
import json;
import base64;
import from PIL { Image }
import from core.theming.tokens { DEFAULT_THEME, validate_theme }
import from core.theming.branding { parse_theme }
import from tests.support.served { Served }
import from tests.support.payment_setup { paying_cinema, hire }

def _logo_base64 -> str {
    img = Image.new("RGBA", (120, 120), (0, 0, 0, 0));
    for x in range(20, 100) {
        for y in range(20, 100) {
            img.putpixel((x, y), (120, 20, 30, 255) if x < 60 else (230, 180, 40, 255));
        }
    }
    out = io.BytesIO();
    img.save(out, "PNG");
    return base64.b64encode(out.getvalue()).decode();
}

def _proposal(name: str) -> str {
    # The model's answer: one theme on the default colours with a red accent, as JSON.
    light = dict(DEFAULT_THEME.light.as_dict());
    light["accent"] = "#78141e";
    return json.dumps(
        {
            "mood": name,
            "reason": "Red and gold, like the logo.",
            "light": light,
            "dark": DEFAULT_THEME.dark.as_dict(),
            "display_font": "Bebas Neue",
            "body_font": "Outfit",
            "radius": "medium",
            "scheme": "dark",
            "template": "compact"
        }
    );
}

def _suggest(app: Served, who: str = "owner") -> any {  # jac:ignore[W1037]
    return app.call(who, "suggest_themes", {"tenant": "nova"});
}

test "suggestions need a logo, and come back readable without saving anything" {
    (app, _, _) = paying_cinema([]);
    try {
        refused = _suggest(app);
        assert not refused["ok"] and refused["error"]["code"] == "no_logo" , refused;
        uploaded = app.call(
            "owner",
            "upload_logo",
            {
                "tenant": "nova",
                "content_type": "image/png",
                "data_base64": _logo_base64()
            }
        );
        assert uploaded["ok"] , uploaded;
        before = app.call("owner", "get_branding", {"tenant": "nova"})["branding"][
            "draft"
        ];
        app.call(
            "owner", "script_theme_model", {"outputs": [_proposal("Crimson Premiere")]}
        );
        got = _suggest(app);
        assert got["ok"] and got["from_ai"] , got;
        assert [p["theme"]["name"] for p in got["proposals"]] == ["Crimson Premiere"];
        for p in got["proposals"] {
            assert validate_theme(parse_theme(p["theme"])) == [];
        }
        assert got["proposals"][0]["template"] == "compact" , "the layout the model chose";
        assert got["proposals"][0]["theme"]["scheme"] == "dark";
        assert got["colours"] and got["colours"][0]["hex"].startswith("#");
        assert got["remaining"] == 4;
        after = app.call("owner", "get_branding", {"tenant": "nova"})["branding"][
            "draft"
        ];
        assert after["theme"] == before["theme"] , "suggesting saves nothing";
    } finally {
        app.close();
    }
}

test "a failing model still answers, and the sixth ask in a day is refused" {
    (app, _, _) = paying_cinema(["agent"]);
    try {
        app.call(
            "owner",
            "upload_logo",
            {
                "tenant": "nova",
                "content_type": "image/png",
                "data_base64": _logo_base64()
            }
        );
        app.call("owner", "script_theme_model", {"outputs": ["not themes"] * 5});
        for left in [4, 3, 2, 1, 0] {
            got = _suggest(app);
            assert got["ok"] and not got["from_ai"] , got;
            assert len(got["proposals"]) == 1;
            assert got["proposals"][0]["theme"]["name"] == "From your logo";
            assert got["remaining"] == left;
        }
        limited = _suggest(app);
        assert not limited["ok"]
            and limited["error"]["code"] == "suggest_limit" , limited;
        # Box office staff don't change branding, so they can't ask either.
        hire(app, "agent", "box_office_agent", "");
        assert not _suggest(app, "agent")["ok"];
    } finally {
        app.close();
    }
}
