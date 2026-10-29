"""P15.6b: how long a shift lasts.

(Reading a count back in words is client code: e2e/reconcile_tests.jac checks it.)
- A shift lasts the cinema's hours (8 unless changed); AFRICINEMAS_SHIFT_TTL_S
  overrides it for tests and dev.
"""

import os;
import from core.tenancy.shifts { shift_ttl_s, TTL_ENV }

test "a shift lasts the cinema's hours, unless the environment says otherwise" {
    kept = os.environ.pop(TTL_ENV, None);
    try {
        assert shift_ttl_s() == 8 * 3600;
        assert shift_ttl_s(6) == 6 * 3600;
        assert shift_ttl_s(0) == 8 * 3600;
        os.environ[TTL_ENV] = "60";
        assert shift_ttl_s(6) == 60;
    } finally {
        os.environ.pop(TTL_ENV, None);
        if kept is not None {
            os.environ[TTL_ENV] = kept;
        }
    }
}
