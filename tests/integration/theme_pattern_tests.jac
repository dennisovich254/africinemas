"""A pattern drawn from the logo, through the endpoints (ADR-0045).

In-process app (payment_app.jac) with the image model scripted (script_pattern).
- draw_pattern needs the draft logo and tenant.settings.update; the drawing is the
  draft's, private until published, worn in the style the model picks (or the owner's).
- Publishing puts it and its style on the storefront; removing it and publishing
  takes it off. A failed drawing says so; PATTERN_DAILY (3) a day per cinema.
"""

import io;
import base64;
import from PIL { Image }
import from core.theming.tokens { DEFAULT_THEME }
import from tests.support.served { Served }
import from tests.support.payment_setup { paying_cinema, hire }

def _png_base64(colour: tuple[int, int, int]) -> str {
    out = io.BytesIO();
    Image.new("RGB", (300, 200), colour).save(out, "PNG");
    return base64.b64encode(out.getvalue()).decode();
}

def _call(app: Served, name: str, args: dict[str, any], who: str = "owner") -> any {  # jac:ignore[W1037]
    return app.call(who, name, {"tenant": "nova", ** args});
}

def _draw(app: Served, who: str = "owner") -> any {  # jac:ignore[W1037]
    return _call(app, "draw_pattern", {"theme": DEFAULT_THEME.as_dict()}, who);
}

def _public(app: Served) -> dict[str, any] {  # jac:ignore[W1037]
    app.client.set_auth_token("");
    resp = app.client.post("/function/public_branding", json={"slug": "nova"});
    return resp.data["result"]["branding"];
}

test "a pattern is drawn from the logo, styled, published, and taken off again" {
    (app, _, _) = paying_cinema([]);
    try {
        refused = _draw(app);
        assert not refused["ok"] and refused["error"]["code"] == "no_logo" , refused;
        _call(
            app,
            "upload_logo",
            {"content_type": "image/png", "data_base64": _png_base64((120, 20, 30))}
        );
        app.call(
            "owner",
            "script_pattern",
            {"image_base64": _png_base64((250, 230, 240)), "style": "spotlight"}
        );
        drawn = _draw(app);
        assert drawn["ok"] , drawn;
        assert drawn["pattern"].startswith("data:image/webp;base64,");
        assert drawn["style"] == "spotlight" , "the model's pick";
        assert drawn["remaining"] == 2;
        assert _public(app)["pattern"] == "" , "a drawing is private until published";
        styled = _call(app, "set_pattern_style", {"style": "framed"});
        assert styled["ok"] and styled["style"] == "framed" , styled;
        bad = _call(app, "set_pattern_style", {"style": "everywhere"});
        assert not bad["ok"] and bad["error"]["code"] == "invalid_style";
        assert _call(app, "publish_theme", {})["ok"];
        shown = _public(app);
        assert shown["pattern"].startswith("data:image/webp;base64,");
        assert shown["pattern_style"] == "framed";
        assert _call(app, "remove_pattern", {})["ok"];
        assert _call(app, "publish_theme", {})["ok"];
        gone = _public(app);
        assert gone["pattern"] == "" and gone["pattern_style"] == "";
    } finally {
        app.close();
    }
}

test "a failed drawing says so, the fourth in a day is refused, box office can't draw" {
    (app, _, _) = paying_cinema(["agent"]);
    try {
        _call(
            app,
            "upload_logo",
            {"content_type": "image/png", "data_base64": _png_base64((20, 60, 120))}
        );
        app.call("owner", "script_pattern", {"image_base64": "", "style": "spotlight"});
        failed = _draw(app);
        assert not failed["ok"]
            and failed["error"]["code"] == "pattern_failed" , failed;
        app.call(
            "owner",
            "script_pattern",
            {"image_base64": _png_base64((240, 240, 255)), "style": "spotlight"}
        );
        assert _draw(app)["ok"];
        assert _draw(app)["ok"];
        limited = _draw(app);
        assert not limited["ok"]
            and limited["error"]["code"] == "pattern_limit" , limited;
        hire(app, "agent", "box_office_agent", "");
        assert not _draw(app, "agent")["ok"];
    } finally {
        app.close();
    }
}
