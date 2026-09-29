"""How cinema-setup endpoints answer (P3.1, P3.2).

An endpoint's work raises instead of returning early: NotFound, NoShift and Forbidden
from the caller's scope (ADR-0008), or Refused for a request it won't carry out.
`answer` turns those into the shared response shapes
({"ok": False, "error": {"code", "message", ...}}).
"""

import from core.authz.policy { Forbidden }
import from core.authz.context { NoShift, NotFound }
import from core.tenancy.responses { NOT_FOUND, FORBIDDEN, NO_SHIFT, refused }

class Refused(ValueError) {
    # A request refused with a code and message the UI can show, and optional extra
    # fields for the error (e.g. the list of problems with a layout).
    def init(
        self: Refused,
        code: str,
        message: str,
        details: dict[str, any] | None = None  # jac:ignore[W1037]
    ) {
        super.init(message);
        self.code = code;
        self.message = message;
        self.details = details or {};
    }
}

def answer(work: any) -> dict[str, any] {  # jac:ignore[W1037]
    # Runs an endpoint's work, turning its refusals into the shared response shapes.
    try {
        return work();
    } except NotFound {
        return NOT_FOUND;
    } except NoShift {
        return NO_SHIFT;
    } except Forbidden {
        return FORBIDDEN;
    } except Refused as e {
        response: dict[str, any] = refused(e.code, e.message);  # jac:ignore[W1037]
        response["error"].update(e.details);
        return response;
    }
}
