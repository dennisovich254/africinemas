"""Test-only fault injection: prove multi-step operations leave nothing half-done.

`checkpoint("after_group")` raises FaultInjected when the AFRICINEMAS_FAULTS
environment variable names that step (comma-separated). Production never sets it:
deploy/production.env must not define it (tests/unit/config_tests.jac).
"""

import os;

glob FAULTS_ENV: str = "AFRICINEMAS_FAULTS";

class FaultInjected(RuntimeError) {}

def checkpoint(step: str) {
    wanted = os.environ.get(FAULTS_ENV, "");
    if wanted and step in [s.strip() for s in wanted.split(",")] {
        raise FaultInjected(f"injected fault at {step}");
    }
}
