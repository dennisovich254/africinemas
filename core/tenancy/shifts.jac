"""Staff shift sessions (ADR-0006, P2.7a).

Jac's tokens last at least a day and can't be revoked, so staff actions also need a live
shift on the server. A shift is an atomic claim (ADR-0007) keyed by (cinema, member)
with a time-to-live: one database lookup to check, gone on its own when it lapses, and
closed at once by end_shift (the UI calls it on logout). Default length: 8 hours.
"""

import os;
import from core.claims { claim, holder, renew, release }

glob SHIFT_CLAIMS: str = "staff-shift",
     TTL_ENV: str = "AFRICINEMAS_SHIFT_TTL_S",
     TTL_DEFAULT_S: int = 8 * 3600;

def shift_ttl_s -> int {
    return int(os.environ.get(TTL_ENV, str(TTL_DEFAULT_S)));
}

def _key(tenant_id: str, member_id: str) -> str {
    return f"{tenant_id}:{member_id}";
}

def open_shift(tenant_id: str, member_id: str) -> int {
    # Opens (or restarts) the member's shift; returns its length in seconds.
    ttl = shift_ttl_s();
    key = _key(tenant_id, member_id);
    if claim(SHIFT_CLAIMS, key, member_id, ttl) == member_id {
        renew(SHIFT_CLAIMS, key, member_id, ttl);
    }
    return ttl;
}

def shift_is_open(tenant_id: str, member_id: str) -> bool {
    return holder(SHIFT_CLAIMS, _key(tenant_id, member_id)) == member_id;
}

def close_shift(tenant_id: str, member_id: str) {
    release(SHIFT_CLAIMS, _key(tenant_id, member_id), member_id);
}
