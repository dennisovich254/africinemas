"""A brand kit drawn from the logo, through the endpoints (ADR-0046).

In-process app (payment_app.jac) with the plan and image models scripted
(script_brand_kit).
- draw_brand_kit needs the draft logo and tenant.settings.update; the kit is the
  draft's, private until published; set_brand_look changes parts of its designed look
  and keeps the rest of what the AI chose (ADR-0047).
- Publishing puts it on the storefront, masks as images; removing it and publishing
  takes it off. KIT_DAILY (3) a day per cinema.
"""

import io;
import json;
import base64;
import from PIL { Image, ImageDraw }
import from tests.support.served { Served }
import from tests.support.payment_setup { paying_cinema, hire }

glob PLAN: str = json.dumps(
         {
             "motifs": ["a dove in flight"],
             "card": "notched",
             "frame": "open",
             "divider": "motif",
             "heading": "caps",
             "fonts": "heritage",
             "header": "centred",
             "hero": "centred_crest",
             "surfaces": "flat",
             "density": "airy",
             "tagline": "Stories under the acacia"
         }
     );

def _png_base64(drawn: bool) -> str {
    img = Image.new("RGB", (300, 300), (255, 255, 255));
    if drawn {
        ImageDraw.Draw(img).ellipse((60, 90, 240, 210), fill=(0, 0, 0));
    } else {
        img = Image.new("RGB", (300, 200), (120, 20, 30));
    }
    out = io.BytesIO();
    img.save(out, "PNG");
    return base64.b64encode(out.getvalue()).decode();
}

def _call(app: Served, name: str, args: dict[str, any], who: str = "owner") -> any {  # jac:ignore[W1037]
    return app.call(who, name, {"tenant": "nova", ** args});
}

def _public(app: Served) -> dict[str, any] {  # jac:ignore[W1037]
    app.client.set_auth_token("");
    resp = app.client.post("/function/public_branding", json={"slug": "nova"});
    return resp.data["result"]["branding"];
}

def _logo(app: Served) {
    assert _call(
        app,
        "upload_logo",
        {"content_type": "image/png", "data_base64": _png_base64(False)}
    )["ok"];
}

test "a kit is drawn from the logo, restyled, published, and taken off again" {
    (app, _, _) = paying_cinema([]);
    try {
        refused = _call(app, "draw_brand_kit", {});
        assert not refused["ok"] and refused["error"]["code"] == "no_logo" , refused;
        _logo(app);
        app.call(
            "owner",
            "script_brand_kit",
            {"image_base64": _png_base64(True), "plan": PLAN}
        );
        drawn = _call(app, "draw_brand_kit", {});
        assert drawn["ok"] , drawn;
        assert drawn["kit"]["look"]["frame"] == "open";
        assert drawn["kit"]["look"]["fonts"] == "heritage";
        assert drawn["kit"]["look"]["hero"] == "centred_crest";
        assert drawn["kit"]["tagline"] == "Stories under the acacia";
        motifs = drawn["kit"]["motifs"];
        assert len(motifs) == 1 and motifs[0]["name"] == "a dove in flight";
        assert motifs[0]["mask"].startswith("data:image/webp;base64,");
        assert drawn["remaining"] == 2;
        assert _public(app)["kit"] == {} , "a kit is private until published";
        restyled = _call(
            app,
            "set_brand_look",
            {
                "look": {
                    "card": "rounded",
                    "frame": "none",
                    "divider": "row",
                    "heading": "natural"
                }
            }
        );
        assert restyled["ok"] and restyled["look"]["card"] == "rounded" , restyled;
        assert restyled["look"]["fonts"] == "heritage" , "the rest of the AI's look stays";
        bad = _call(app, "set_brand_look", {"look": {"card": "blob"}});
        assert not bad["ok"] and bad["error"]["code"] == "invalid_look";
        assert _call(app, "publish_theme", {})["ok"];
        shown = _public(app)["kit"];
        assert shown["look"]["card"] == "rounded";
        assert shown["look"]["header"] == "centred";
        assert shown["tagline"] == "Stories under the acacia";
        assert shown["motifs"][0]["mask"].startswith("data:image/webp;base64,");
        assert _call(app, "remove_brand_kit", {})["ok"];
        assert _call(app, "publish_theme", {})["ok"];
        assert _public(app)["kit"] == {};
    } finally {
        app.close();
    }
}

test "the fourth kit in a day is refused, and box office staff can't draw one" {
    (app, _, _) = paying_cinema(["agent"]);
    try {
        _logo(app);
        app.call(
            "owner",
            "script_brand_kit",
            {"image_base64": _png_base64(True), "plan": PLAN}
        );
        for _ in range(3) {
            assert _call(app, "draw_brand_kit", {})["ok"];
        }
        limited = _call(app, "draw_brand_kit", {});
        assert not limited["ok"] and limited["error"]["code"] == "kit_limit" , limited;
        hire(app, "agent", "box_office_agent", "");
        assert not _call(app, "draw_brand_kit", {}, "agent")["ok"];
        no_kit = _call(
            app,
            "set_brand_look",
            {
                "look": {
                    "card": "rounded",
                    "frame": "none",
                    "divider": "line",
                    "heading": "natural"
                }
            },
            "agent"
        );
        assert not no_kit["ok"];
    } finally {
        app.close();
    }
}

test "design my storefront puts a theme and the brand's design on the draft, privately" {
    (app, _, _) = paying_cinema(["agent"]);
    try {
        refused = _call(app, "design_storefront", {});
        assert not refused["ok"] and refused["error"]["code"] == "no_logo" , refused;
        _logo(app);
        app.call(
            "owner",
            "script_brand_kit",
            {"image_base64": _png_base64(True), "plan": PLAN}
        );
        # The theme model fails, so the theme is built from the logo's colour.
        app.call("owner", "script_theme_model", {"outputs": ["not a theme"] * 3});
        designed = _call(app, "design_storefront", {});
        assert designed["ok"] , designed;
        assert designed["theme"]["name"] == "From your logo";
        assert designed["kit"]["look"]["hero"] == "centred_crest";
        assert designed["remaining"] == 2;
        draft = app.call("owner", "get_branding", {"tenant": "nova"})["branding"][
            "draft"
        ];
        assert draft["theme"]["name"] == "From your logo" , "the theme is the draft's";
        assert draft["kit"]["look"]["fonts"] == "heritage";
        assert _public(app)["kit"] == {} , "private until published";
        # It shares the kit's daily limit, and box office staff can't use it.
        assert _call(app, "draw_brand_kit", {})["ok"];
        assert _call(app, "design_storefront", {})["ok"];
        limited = _call(app, "design_storefront", {});
        assert not limited["ok"] and limited["error"]["code"] == "kit_limit" , limited;
        hire(app, "agent", "box_office_agent", "");
        assert not _call(app, "design_storefront", {}, "agent")["ok"];
    } finally {
        app.close();
    }
}
