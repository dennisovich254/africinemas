"""P15.0: every key the site keeps in the visitor's browser is in the cookie notice.

The notice (core/legal/published/cookies.md, from docs/legal/cookies-and-storage.md)
lists what's kept in local and session storage. This reads every web file that uses
either, takes each "africinemas…" or "jac_token" text in it (up to any `{…}` filled in
at run time), and checks the notice names it. A new key fails here until the notice
lists it. NOT_KEYS are texts in those files that aren't storage keys, or keys only a
switched-off feature writes, each with why.
"""

import os;
import re;

glob ROOT: str = os.path.dirname(
         os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
     ),
     NOTICE: str = os.path.join(ROOT, "core", "legal", "published", "cookies.md"),
     NOT_KEYS: dict[str, str] = {
         "africinemas-venue": "the event that tells every venue picker of a change",
         "africinemas-setup-guide": "the event that hides the setup guide everywhere",
         # Written only by the booking chat, which is off (owner, 2026-10-26), so the
         # published notice leaves it out (scripts/publish_legal.py). Remove this
         # when the chat comes back: the notice must list it again.
         "africinemas:chat:": "the booking chat's conversation, while the chat is off"
     },
     LITERAL: str = '"((?:africinemas|jac_token)[^"{]*)';

def storage_keys -> dict[str, str] {
    # Each key's fixed part, and the file it's in.
    found: dict[str, str] = {};
    for (folder, _, names) in os.walk(os.path.join(ROOT, "web")) {
        for name in names {
            if not name.endswith(".jac") {
                continue;
            }
            path = os.path.join(folder, name);
            with open(path, encoding="utf-8") as f {
                text = f.read();
            }
            if "localStorage" not in text and "sessionStorage" not in text {
                continue;
            }
            for key in re.findall(LITERAL, text) {
                if key not in NOT_KEYS {
                    found[key] = os.path.relpath(path, ROOT);
                }
            }
        }
    }
    return found;
}

test "every browser-storage key is listed in the cookie notice" {
    with open(NOTICE, encoding="utf-8") as f {
        notice = f.read();
    }
    keys = storage_keys();
    # The ones known today, so a scan that finds nothing can't pass.
    for known in ["africinemas:holder", "africinemas_site", "jac_token"] {
        assert known in keys , (known, keys);
    }
    missing = [
        f"{key} ({where})"
        for (key, where) in sorted(keys.items())
        if key not in notice
    ];
    assert missing == [] , f"not in the cookie notice: {missing}";
}
