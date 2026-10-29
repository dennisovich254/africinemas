"""Staff shift sessions (ADR-0006, P2.7a).

Jac's tokens last at least a day and can't be revoked, so staff actions also need a live
shift on the server. A shift is an atomic claim (ADR-0007) keyed by (cinema, member)
with a time-to-live: one database lookup to check, gone on its own when it lapses, and
closed at once by end_shift (the UI calls it on logout), or by counting the cash
(P15.6b). Its length is the cinema's (`Tenant.shift_hours`, 8 by default, set on
Settings → Box office); AFRICINEMAS_SHIFT_TTL_S overrides it for tests and dev.
When it started is kept beside it (SHIFT_STARTS), for "count your last shift first".
"""

import os;
import from core.clock { now }
import from core.claims { claim, holder, renew, release }

glob SHIFT_CLAIMS: str = "staff-shift",
     SHIFT_STARTS: str = "staff-shift-start",
     TTL_ENV: str = "AFRICINEMAS_SHIFT_TTL_S",
     TTL_DEFAULT_S: int = 8 * 3600;

def shift_ttl_s(hours: int = 0) -> int {
    # The environment's override, else the cinema's hours, else 8 hours.
    if os.environ.get(TTL_ENV) {
        return int(os.environ[TTL_ENV]);
    }
    return hours * 3600 if hours > 0 else TTL_DEFAULT_S;
}

def _key(tenant_id: str, member_id: str) -> str {
    return f"{tenant_id}:{member_id}";
}

def open_shift(tenant_id: str, member_id: str, hours: int = 0) -> int {
    # Opens (or restarts) the member's shift for the cinema's `hours`; returns its length
    # in seconds. A shift that's still open keeps the time it started.
    ttl = shift_ttl_s(hours);
    key = _key(tenant_id, member_id);
    if claim(SHIFT_CLAIMS, key, member_id, ttl) == member_id {
        renew(SHIFT_CLAIMS, key, member_id, ttl);
    }
    started = now().isoformat();
    kept = claim(SHIFT_STARTS, key, started, ttl);
    renew(SHIFT_STARTS, key, kept, ttl);
    return ttl;
}

def shift_started_at(tenant_id: str, member_id: str) -> str {
    # When the member's open shift started, or "" when none is open.
    if not shift_is_open(tenant_id, member_id) {
        return "";
    }
    return holder(SHIFT_STARTS, _key(tenant_id, member_id)) or "";
}

def shift_is_open(tenant_id: str, member_id: str) -> bool {
    return holder(SHIFT_CLAIMS, _key(tenant_id, member_id)) == member_id;
}

def close_shift(tenant_id: str, member_id: str) {
    key = _key(tenant_id, member_id);
    release(SHIFT_CLAIMS, key, member_id);
    started = holder(SHIFT_STARTS, key);
    if started {
        release(SHIFT_STARTS, key, started);
    }
}
