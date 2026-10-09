"""A movie's trailer link (P8.1): only https YouTube or Vimeo, in one canonical form.

The link is shown to customers (the storefront, the AI chat), so it's checked like any
input that ends up in a page: parsed, its host matched exactly, its video id matched
against the provider's id format, and rebuilt from the id, so nothing else in the
link survives. trailer_embed gives the URL players embed: YouTube's no-cookie domain,
Vimeo's player.
"""

import re;
import from urllib.parse { urlparse, parse_qs }

glob LINK_MAX: int = 500,
     YOUTUBE_HOSTS: list[str] = ["youtube.com", "www.youtube.com", "m.youtube.com"],
     VIMEO_HOSTS: list[str] = ["vimeo.com", "www.vimeo.com", "player.vimeo.com"],
     YOUTUBE_ID: str = r"^[A-Za-z0-9_-]{11}$",
     VIMEO_ID: str = r"^[0-9]{1,12}$";

class TrailerRejected(ValueError) {}

def _youtube_id(host: str, path: str, query: str) -> str {
    # The video id of a YouTube link, or "".
    found = "";
    if host == "youtu.be" {
        found = path.strip("/").split("/")[0];
    } elif host in YOUTUBE_HOSTS {
        parts = [
            p
            for p in path.split("/")
            if p
        ];
        if parts == ["watch"] {
            found = (parse_qs(query).get("v") or [""])[0];
        } elif len(parts) == 2 and parts[0] in ["embed", "shorts"] {
            found = parts[1];
        }
    }
    return found if re.fullmatch(YOUTUBE_ID, found) else "";
}

def _vimeo_id(host: str, path: str) -> str {
    # The video id of a Vimeo link, or "".
    parts = [
        p
        for p in path.split("/")
        if p
    ];
    found = "";
    if host in ["vimeo.com", "www.vimeo.com"] and len(parts) == 1 {
        found = parts[0];
    } elif host == "player.vimeo.com" and len(parts) == 2 and parts[0] == "video" {
        found = parts[1];
    }
    return found if re.fullmatch(VIMEO_ID, found) else "";
}

def clean_trailer(text: str) -> str {
    # The canonical link for a YouTube or Vimeo trailer, "" to clear it. Raises
    # TrailerRejected for anything else.
    link = (text or "").strip();
    if not link {
        return "";
    }
    if len(link) > LINK_MAX {
        raise TrailerRejected("That link is too long.");
    }
    parsed = urlparse(link);
    host = (parsed.hostname or "").lower();
    if parsed.scheme != "https" or parsed.username or parsed.password or parsed.port {
        raise TrailerRejected("Use an https link to YouTube or Vimeo.");
    }
    video = _youtube_id(host, parsed.path, parsed.query);
    if video {
        return f"https://www.youtube.com/watch?v={video}";
    }
    video = _vimeo_id(host, parsed.path);
    if video {
        return f"https://vimeo.com/{video}";
    }
    raise TrailerRejected("Use a link to a YouTube or Vimeo video.");
}

def trailer_embed(link: str) -> str {
    # The embeddable player URL for a canonical trailer link, "" for none.
    if not link {
        return "";
    }
    parsed = urlparse(link);
    host = (parsed.hostname or "").lower();
    video = _youtube_id(host, parsed.path, parsed.query);
    if video {
        return f"https://www.youtube-nocookie.com/embed/{video}";
    }
    video = _vimeo_id(host, parsed.path);
    return f"https://player.vimeo.com/video/{video}" if video else "";
}
