"""Help with connecting M-Pesa (P15.3): AfriCinemas' own setup video.

A super admin (platform.settings) records the Daraja go-live steps once and pastes the
video's link in the console (Fees); every cinema's Settings -> Payments shows it above
the written steps. A YouTube link plays on the page, from youtube-nocookie.com (no
tracking cookies until it's played); any other https link opens in a new tab. No link,
no video box. One permanent claim holds it, and every change goes to the platform audit
log.

Booking a setup call needs nothing here: the Payments page files a Help request
(core/support/requests.jac, category "setup_call") that support answers in the console.
"""

import re;
import json;
import from urllib.parse { urlparse, parse_qs }
import from core.clock { now }
import from core.claims { claim, holder, take_claim }
import from core.catalog.answers { Refused, answer }
import from core.platform.staff_api { require_platform }
import from core.audit.log { platform_audited }

glob SPACE: str = "platform-setting",
     KEY: str = "mpesa_guide_video",
     URL_MAX: int = 300,
     VIDEO_ID: re.Pattern[str] = re.compile(r"^[A-Za-z0-9_-]{6,20}$"),
     YOUTUBE: list[str] = ["youtube.com", "www.youtube.com", "m.youtube.com"];

def embed_of(url: str) -> str {
    # The privacy-friendly player address for a YouTube link, or "" for anything else.
    parts = urlparse(url);
    host = (parts.hostname or "").lower();
    found = "";
    if host == "youtu.be" {
        found = parts.path.strip("/");
    } elif host in YOUTUBE {
        if parts.path == "/watch" {
            found = (parse_qs(parts.query).get("v") or [""])[0];
        } elif parts.path.startswith(("/embed/", "/shorts/", "/live/")) {
            found = parts.path.split("/")[2];
        }
    }
    if not VIDEO_ID.match(found) {
        return "";
    }
    return f"https://www.youtube-nocookie.com/embed/{found}";
}

def guide_video -> dict[str, str] {
    # {"url", "embed", "by", "at"}: url "" when none is set.
    kept = holder(SPACE, KEY);
    if not kept {
        return {"url": "", "embed": "", "by": "", "at": ""};
    }
    found = json.loads(kept);
    return {** found, "embed": embed_of(found["url"]) if found["url"] else ""};
}

def _get -> dict[str, any] {  # jac:ignore[W1037]
    require_platform("platform.read");
    return {"ok": True, "video": guide_video()};
}

def _set(url: str, who: str) -> dict[str, any] {  # jac:ignore[W1037]
    clean = url.strip() if isinstance(url, str) else "";
    if clean {
        parts = urlparse(clean);
        if parts.scheme != "https"
            or not parts.hostname
            or len(clean) > URL_MAX
            or any([c in clean for c in " <>\"'"]) {
            raise Refused(
                "invalid_url",
                f"Paste the video's https link, up to {URL_MAX} characters."
            );
        }
    }
    take_claim(SPACE, KEY);
    claim(SPACE, KEY, json.dumps({"url": clean, "by": who, "at": now().isoformat()}));
    return {"ok": True, "video": guide_video()};
}

def:protect mpesa_guide_video -> dict[str, any] {  # jac:ignore[W1037]
    return answer(_get);
}

def:protect set_mpesa_guide_video(url: str) -> dict[str, any] {  # jac:ignore[W1037]
    try {
        me = require_platform("platform.settings");
    } except Refused as e {
        return {"ok": False, "error": {"code": e.code, "message": e.message}};
    }
    return platform_audited(
        me.root_id,
        me.email,
        "platform.mpesa_video_set",
        "setting",
        KEY,
        lambda -> any { return _set(url, me.email); },  # jac:ignore[W1037]
        detail=str(url or "")[:URL_MAX]
    );
}
