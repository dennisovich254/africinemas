"""Words a cinema can't use to look verified (P14.5, ADR-0071).

The Verified badge is ours alone: drawn from our records and checkable on our own site.
So the text a cinema writes itself can't imitate it:
- **names** (the cinema's name, its registered business name, a document's title)
  can't contain "verified" or "AfriCinemas";
- **longer text** (the home page, policies, directions and other website information)
  can't claim the badge: "verified cinema", "verified by AfriCinemas", "AfriCinemas
  verified" and the like. Mentioning AfriCinemas otherwise is fine: our own privacy
  template says AfriCinemas runs the site.
"""

import re;

glob NAME_WORDS: str = r"verif|afri\W*cinemas",
     BADGE_CLAIM: str = r"verified\W+(cinema|venue|business|partner|by\W+afri\W*cinemas)|(afri\W*cinemas|officially)\W+verified|[✓✔☑]\W*verified",
     NAME_MESSAGE: str = "Leave out \"verified\" and \"AfriCinemas\": AfriCinemas shows your Verified badge itself.",
     TEXT_MESSAGE: str = "Leave out claims like \"verified cinema\": AfriCinemas shows your Verified badge itself.";

def name_claims(text: str) -> bool {
    # Whether a name uses our words.
    return bool(re.search(NAME_WORDS, text or "", re.IGNORECASE));
}

def text_claims(text: str) -> bool {
    # Whether longer text claims the Verified badge.
    return bool(re.search(BADGE_CLAIM, text or "", re.IGNORECASE));
}
