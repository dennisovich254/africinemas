"""Spike S6 fallback (plan P1.4): short, revocable staff sessions kept on the server.

Jac tokens last at least a day, can't be revoked and sit in the browser's
localStorage (ADR-0006). So staff actions also require a live server-side shift
session: it expires after SHIFT_HOURS and ends the moment the staff member logs out
(or is removed), whatever the token says. Sessions are system-owned, like the receipt
inbox (ADR-0005), so a staff member can't extend their own.
"""

import from datetime { datetime, timedelta }
import from jaclang { JacRuntime as Jac }
import from core.clock { now }
import from core.tenancy.principal {
    node_id,
    act_as,
    restore,
    flush_now,
    system_root_id
}

glob SHIFT_HOURS: int = 8;

node SessionRegistry {}

node StaffSession {
    has staff_root_id: str,
        expires_at: str;
}

def _registry -> SessionRegistry {
    # Call while acting as the system root.
    found = [root-->[?:SessionRegistry]];
    if found {
        return found[0];
    }
    reg = SessionRegistry();
    root ++> reg;
    return reg;
}

def _sessions_of(staff_root_id: str) -> list[StaffSession] {
    return [
        s
        for s in [_registry()-->[?:StaffSession]]
        if s.staff_root_id == staff_root_id
    ];
}

def:priv s6_start_shift -> dict[str, str] {
    me = node_id(root);
    act_as(system_root_id());
    try {
        for old in _sessions_of(me) {
            Jac.destroy([old]);
        }
        session = StaffSession(
            staff_root_id=me,
            expires_at=(now() + timedelta(hours=SHIFT_HOURS)).isoformat()
        );
        _registry() ++> session;
        flush_now();
        return {"expires_at": session.expires_at};
    } finally {
        restore(me);
    }
}

def:priv s6_end_shift -> dict[str, int] {
    me = node_id(root);
    act_as(system_root_id());
    try {
        ended = 0;
        for old in _sessions_of(me) {
            Jac.destroy([old]);
            ended += 1;
        }
        flush_now();
        return {"ended": ended};
    } finally {
        restore(me);
    }
}

def:priv s6_staff_action -> dict[str, any] {
    # What every staff endpoint will check, next to membership (ADR-0004).
    me = node_id(root);
    act_as(system_root_id());
    try {
        live = any(
            datetime.fromisoformat(s.expires_at) > now() for s in _sessions_of(me)
        );
    } finally {
        restore(me);
    }
    return {"allowed": live};
}
