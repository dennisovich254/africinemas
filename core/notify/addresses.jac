"""Email addresses where a customer's tickets go (P6.3, ADR-0010).

The check is deliberately plain, and the pay form (web/storefront/checkout_rules.jac)
makes the same one: a local part and a dotted domain, no spaces, at most 254
characters. Whether the address really reaches someone only sending shows; a mistyped
one is fixed by resending to a corrected address.
"""

glob MAX_LENGTH: int = 254,
     WANTED: str = "Enter the email address for your tickets, like name@example.com.",
     DOMAIN_CHARS: str = "abcdefghijklmnopqrstuvwxyz0123456789-";

def email_problem(text: str) -> str {
    # Why this isn't a usable address ("" if it is).
    address = text.strip();
    if len(address) == 0 or len(address) > MAX_LENGTH or address.count("@") != 1 {
        return WANTED;
    }
    (local, _, domain) = address.partition("@");
    labels = domain.lower().split(".");
    if len(local) == 0
        or any([ch.isspace() for ch in address])
        or len(labels) < 2
        or any(
            [len(l) == 0 or any([ch not in DOMAIN_CHARS for ch in l]) for l in labels]
        )
        or len(labels[len(labels) - 1]) < 2 {
        return WANTED;
    }
    return "";
}

def clean_email(text: str) -> str {
    # The address as stored: trimmed, its domain in lower case.
    (local, _, domain) = text.strip().partition("@");
    return f"{local}@{domain.lower()}";
}

def masked_email(address: str) -> str {
    # How an address is shown on screen: "d*****@gmail.com".
    (local, _, domain) = address.partition("@");
    return f"{local[:1]}{'*' * (len(local) - 1)}@{domain}";
}
