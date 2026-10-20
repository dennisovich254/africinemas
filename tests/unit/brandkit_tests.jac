"""A cinema's brand kit from its logo (ADR-0046): the plan, the masks, the look.

No network: the plan model is a MockLLM and the image call (`send`) is replaced. Only
designed look values survive; a drawing becomes a mask (dark is shape, white is clear) or
is dropped; a failing plan gives no motifs and the default look.
"""

import io;
import base64;
import from PIL { Image, ImageDraw }
import from jaclang.byllm.lib { MockLLM }
import core.theming.brandkit as brandkit;
import from core.theming.brandkit {
    BrandPlan,
    CardStyle,
    FrameStyle,
    DividerStyle,
    HeadingStyle,
    KitFailed,
    DEFAULT_LOOK,
    MASK_SIDE,
    as_mask,
    checked_look,
    plan_kit,
    draw_kit
}

def _png(img: any) -> bytes {  # jac:ignore[W1037]
    out = io.BytesIO();
    img.save(out, "PNG");
    return out.getvalue();
}

def _dove_drawing -> bytes {
    # A black blob on white, as the image model draws a silhouette.
    img = Image.new("RGB", (600, 600), (255, 255, 255));
    ImageDraw.Draw(img).ellipse((150, 200, 450, 400), fill=(0, 0, 0));
    return _png(img);
}

def _answer(raw: bytes) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "candidates": [
            {
                "content": {
                    "parts": [{"inlineData": {"data": base64.b64encode(raw).decode()}}]
                }
            }
        ]
    };
}

test "a black drawing on white becomes a shape on clear, cropped and small" {
    mask = Image.open(io.BytesIO(as_mask(_dove_drawing())));
    assert mask.format == "WEBP" and mask.mode == "RGBA";
    assert max(mask.size) <= MASK_SIDE;
    (w, h) = mask.size;
    assert mask.getpixel((w // 2, h // 2))[3] > 200 , "the middle is shape";
    assert mask.getpixel((0, 0))[3] < 40 , "the corner is clear";
}

test "a transparent drawing keeps its transparency; blank or solid drawings are refused" {
    clear = Image.new("RGBA", (300, 300), (0, 0, 0, 0));
    ImageDraw.Draw(clear).ellipse((60, 60, 240, 240), fill=(0, 0, 0, 255));
    assert Image.open(io.BytesIO(as_mask(_png(clear)))).mode == "RGBA";
    for bad in [
        _png(Image.new("RGB", (300, 300), (255, 255, 255))),
        _png(Image.new("RGB", (300, 300), (0, 0, 0))),
        b"<svg onload=alert(1)>"
    ] {
        try {
            as_mask(bad);
            assert False , "must be refused";
        } except KitFailed {}
    }
}

test "a look is four designed choices, nothing else" {
    good = {"card": "notched", "frame": "open", "divider": "row", "heading": "caps"};
    assert checked_look(good) == good;
    for bad in [
        {},
        {"card": "blob", "frame": "open", "divider": "row", "heading": "caps"},
        {"card": "notched", "frame": "open", "divider": "row"},
        "notched"
    ] {
        try {
            checked_look(bad);
            assert False , bad;
        } except ValueError {}
    }
}

test "the plan keeps the model's motifs and look; a failure gives the default look" {
    brandkit.plan_model = MockLLM(
        outputs=[
            BrandPlan(
                motifs=["a dove in flight", "three doves", "a third one"],
                card=CardStyle.NOTCHED,
                frame=FrameStyle.OPEN,
                divider=DividerStyle.MOTIF,
                heading=HeadingStyle.CAPS
            )
        ]
    );
    (names, look) = plan_kit(_dove_drawing(), "Rupa's Mall");
    assert names == ["a dove in flight", "three doves"] , "at most two";
    assert look
        == {"card": "notched", "frame": "open", "divider": "motif", "heading": "caps"};
    brandkit.plan_model = MockLLM(outputs=["not a plan"]);
    (none, fallback) = plan_kit(_dove_drawing(), "Rupa's Mall");
    assert none == [] and fallback == DEFAULT_LOOK;
}

test "a kit keeps the motifs that drew; with none, the divider is a plain line" {
    brandkit.plan_model = MockLLM(
        outputs=[
            BrandPlan(
                motifs=["a dove", "a blank"],
                card=CardStyle.SHARP,
                frame=FrameStyle.NONE,
                divider=DividerStyle.ROW,
                heading=HeadingStyle.NATURAL
            )
        ]
    );
    drawings = [_dove_drawing(), _png(Image.new("RGB", (200, 200), (255, 255, 255)))];
    def scripted(_logo: bytes, _brief: str) -> dict[str, any] {  # jac:ignore[W1037]
        return _answer(drawings.pop(0));
    }
    brandkit.send = scripted;
    kit = draw_kit(_dove_drawing(), "Rupa's Mall");
    assert [m["name"] for m in kit["motifs"]] == ["a dove"] , "the blank drawing is left out";
    assert kit["look"]["divider"] == "row";
    brandkit.plan_model = MockLLM(
        outputs=[
            BrandPlan(
                motifs=["a blank"],
                card=CardStyle.SHARP,
                frame=FrameStyle.NONE,
                divider=DividerStyle.MOTIF,
                heading=HeadingStyle.NATURAL
            )
        ]
    );
    def blank(_logo: bytes, _brief: str) -> dict[str, any] {  # jac:ignore[W1037]
        return _answer(_png(Image.new("RGB", (200, 200), (255, 255, 255))));
    }
    brandkit.send = blank;
    bare = draw_kit(_dove_drawing(), "Rupa's Mall");
    assert bare["motifs"] == [] and bare["look"]["divider"] == "line";
}
