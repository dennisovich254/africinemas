"""Test-only fault injection: prove multi-step operations leave nothing half-done.

`checkpoint("after_group")` raises FaultInjected when the AFRICINEMAS_FAULTS
environment variable names that step (comma-separated); `replay_point("x")` forces one
re-run of the request (a WriteConflict) when it names "replay:x". Production never sets it:
deploy/production.env must not define it (tests/unit/config_tests.jac).
"""

import os;
import from uuid { UUID }
import from jaclang { JacRuntime as Jac }
import from jaclang.runtime.exceptions { WriteConflict }

glob FAULTS_ENV: str = "AFRICINEMAS_FAULTS";

class FaultInjected(RuntimeError) {}

def checkpoint(step: str) {
    wanted = os.environ.get(FAULTS_ENV, "");
    if wanted and step in [s.strip() for s in wanted.split(",")] {
        raise FaultInjected(f"injected fault at {step}");
    }
}

glob _REPLAYED: list[str] = [];

def replay_point(step: str) {
    # Forces Jac to re-run the request once, as a write conflict would: raises
    # WriteConflict the first time AFRICINEMAS_FAULTS names "replay:<step>" (once per
    # value of the variable, so a test sets a fresh value to arm it again).
    wanted = os.environ.get(FAULTS_ENV, "");
    names = [s.strip() for s in wanted.split(",")];
    if f"replay:{step}" not in names {
        return;
    }
    fired = f"{wanted}|{step}";
    if fired in _REPLAYED {
        return;
    }
    _REPLAYED.append(fired);
    raise WriteConflict(anchor_id=UUID(str(Jac.get_context().user_root.id)));
}
