"""Staff sign-in, sign-up and sign-out for the back-office (P2.7b).

People sign in with their email address (a Jac `email` identity). Signing out also ends
the shift at the cinemas passed in (ADR-0006): a Jac token can't be revoked, so without
this a copied token would keep working until the shift expired.
"""

import from "@jac/runtime" { jacLogin, jacSignup, jacLogout, SignupResult }
import from core.tenancy.tenant_api { end_shift }  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)

def:pub email_identity(email: str) -> dict[str, str] {
    return {"type": "email", "value": email.strip().lower()};
}

# "ok", "rejected" (wrong email or password) or "offline" (the server couldn't be
# reached). jacLogin returns False for any refusal and throws when the request fails.
async def:pub sign_in(email: str, password: str) -> str {
    ok: bool = False;
    try {
        ok = await jacLogin(email_identity(email), password);
    } except Exception as e {
        console.warn("sign-in request failed", e);
        return "offline";
    }
    return "ok" if ok else "rejected";
}

# Returns "" on success, otherwise a message to show next to the form.
async def:pub sign_up(email: str, password: str) -> str {
    result: SignupResult | None = None;
    signed_in: str = "";
    result = await jacSignup([email_identity(email)], password);
    if not result.success {
        if "already registered" in (result.error or "") {
            return "An account with this email already exists. Sign in instead.";
        }
        return result.error or "We couldn't create your account. Try again.";
    }
    signed_in = await sign_in(email, password);
    if signed_in != "ok" {
        return "Your account was created, but signing in failed. Sign in to continue.";
    }
    return "";
}

async def:pub sign_out(slugs: list[str]) {
    for slug in slugs {
        try {
            await end_shift(slug);  # jac:ignore[W2037]
        } except Exception as e {
            # Still sign out: the shift expires on its own (ADR-0006).
            console.warn("end_shift failed", slug, e);
        }
    }
    jacLogout();
}
