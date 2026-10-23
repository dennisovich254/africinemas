"""Signing in and out of the AfriCinemas platform (P13.1b.a), with a platform account.

A platform account is apart from any cinema account with the same email: its username
is "platform:<local part>:<domain>" (core/platform/accounts.jac), and the console is on
an address of its own (web/site.jac), whose storage no cinema page shares, so its
sign-in never signs anyone in or out of a cinema's back office or storefront.
"""

import from "@jac/runtime" { jacLogin, jacLogout }

def:pub platform_identity(email: str) -> dict[str, str] {
    address = email.strip().lower();
    return {"type": "username", "value": f"platform:{address.replace('@', ':')}"};
}

# "ok", "rejected" (wrong email or password) or "offline" (the server couldn't be
# reached). jacLogin returns False for any refusal and throws when the request fails.
async def:pub platform_sign_in(email: str, password: str) -> str {
    ok: bool = False;
    try {
        ok = await jacLogin(platform_identity(email), password);
    } except Exception as e {
        console.warn("platform sign-in failed", e);
        return "offline";
    }
    return "ok" if ok else "rejected";
}

async def:pub platform_sign_in_as(name: str, password: str) -> bool {
    # Right after joining: the server named the account.
    try {
        return await jacLogin({"type": "username", "value": name}, password);
    } except Exception as e {
        console.warn("platform sign-in failed", e);
    }
    return False;
}

def:pub platform_sign_out {
    jacLogout();
}
