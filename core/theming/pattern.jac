"""A decorative pattern drawn from the cinema's logo (ADR-0045).

Gemini's image model gets the logo itself and the theme the owner is editing, and draws a
light repeating pattern of the logo's own motifs (flowers, birds, shapes...) in the
theme's colours, on the theme's page colour for its scheme. The answer is decoded and
re-encoded here as a WebP no larger than MAX_SIDE, so only a checked image is stored. It
is a direct REST call: byLLM's image generation takes text only, and the logo is the
reference that makes the motifs the cinema's own.

`send` makes the model call; tests replace it (payment_app.script_pattern).
"""

import io;
import os;
import base64;
import logging;
import httpx;
import from PIL { Image as PilImage }
import from core.theming.tokens { Theme }

class PatternFailed(RuntimeError) {}

glob logger = logging.getLogger(__name__),
     MODEL_ENV: str = "AFRICINEMAS_PATTERN_MODEL",
     # Browser tests only (scripts/e2e_env.sh; production never sets it): an image file
     # that stands in for the model's drawing.
     SCRIPT_ENV: str = "AFRICINEMAS_PATTERN_SCRIPT",
     DEFAULT_MODEL: str = "gemini-2.5-flash-image",
     API: str = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
     # A drawing took 13.5 s (2026-10-19); this bounds a slow one.
     TIMEOUT: float = 60.0,
     MAX_SIDE: int = 1024,
     # Where a storefront can show the pattern; the owner picks (Settings > Branding).
     PLACES: list[str] = ["hero", "header", "sections", "footer", "tickets"],
     DEFAULT_PLACES: list[str] = ["hero", "footer"];

def pattern_prompt(theme: Theme) -> str {
    # The drawing brief: the logo's motifs, the theme's colours, its page colour.
    tokens = theme.dark if theme.scheme == "dark" else theme.light;
    colours = ", ".join(
        sorted({tokens.accent, tokens.link, tokens.accent_ink, tokens.muted})
    );
    return (
        "Look at this cinema logo. Draw a seamless, repeating decorative background pattern "
        + "made from the motifs in the logo (its flowers, birds, animals, plants or shapes), "
        + "redrawn simply as flat illustrations in the logo's style. "
        + f"Use only these colours: {colours}, on a plain {tokens.background} background. "
        + "Keep it light and airy with plenty of empty space, so text can sit on top. "
        + "No text, letters, numbers, logos, faces or borders."
    );
}

def _send_gemini(logo_webp: bytes, prompt: str) -> dict[str, any] {  # jac:ignore[W1037]
    scripted = os.environ.get(SCRIPT_ENV, "");
    if scripted and os.path.isfile(scripted) {
        with open(scripted, "rb") as f {
            drawn = base64.b64encode(f.read()).decode();
        }
        return {
            "candidates": [{"content": {"parts": [{"inlineData": {"data": drawn}}]}}]
        };
    }
    key = os.environ.get("GEMINI_API_KEY", "").strip();
    if not key {
        raise PatternFailed("no GEMINI_API_KEY");
    }
    model = os.environ.get(MODEL_ENV) or DEFAULT_MODEL;
    body = {
        "contents": [
            {
                "parts": [
                    {"text": prompt},
                    {
                        "inline_data": {
                            "mime_type": "image/webp",
                            "data": base64.b64encode(logo_webp).decode()
                        }
                    }
                ]
            }
        ],
        "generationConfig": {"responseModalities": ["IMAGE"]}
    };
    try {
        resp = httpx.post(
            API.format(model=model), params={"key": key}, json=body, timeout=TIMEOUT
        );
    } except httpx.HTTPError as e {
        raise PatternFailed(f"{type(e).__name__}: {e}");
    }
    if resp.status_code != 200 {
        raise PatternFailed(f"{resp.status_code}: {resp.text[:300]}");
    }
    return resp.json();
}

glob send: any = _send_gemini;  # jac:ignore[W1037]

def _image_of(answer: dict[str, any]) -> bytes {  # jac:ignore[W1037]
    # The first image in a generateContent answer.
    for candidate in answer.get("candidates", []) or [] {
        for part in (candidate.get("content", {}) or {}).get("parts", []) or [] {
            inline = part.get("inlineData") or part.get("inline_data");
            if inline and inline.get("data") {
                return base64.b64decode(inline["data"]);
            }
        }
    }
    raise PatternFailed("the answer had no image");
}

def as_webp(raw: bytes) -> bytes {
    # The drawing decoded and re-encoded: only a real image, at most MAX_SIDE, is kept.
    try {
        picture = PilImage.open(io.BytesIO(raw));
        picture.load();
    } except Exception as e {
        raise PatternFailed(f"not an image: {type(e).__name__}");
    }
    flat = picture.convert("RGB");
    flat.thumbnail((MAX_SIDE, MAX_SIDE));
    out = io.BytesIO();
    flat.save(out, "WEBP", quality=80);
    return out.getvalue();
}

def draw_pattern(logo_webp: bytes, theme: Theme) -> bytes {
    # A pattern of the logo's motifs in `theme`'s colours, as WebP, or PatternFailed.
    return as_webp(_image_of(send(logo_webp, pattern_prompt(theme))));
}

def checked_places(places: any) -> list[str] {  # jac:ignore[W1037]
    # The allowed places in `places`, each once, in PLACES order; anything else is refused.
    if not isinstance(places, list) or any([p not in PLACES for p in places]) {
        raise ValueError(f"places are some of {PLACES}");
    }
    return [
        p
        for p in PLACES
        if p in places
    ];
}
