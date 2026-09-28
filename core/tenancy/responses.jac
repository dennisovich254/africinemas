"""The one shape tenant endpoints use to refuse: {"ok": False, "error": {"code", "message"}}.

"not_found" never reveals whether a cinema exists (P2.4); "forbidden" is for members
who lack the permission (ADR-0008).
"""

glob NOT_FOUND: dict[str, bool | dict[str, str]] = {
         "ok": False,
         "error": {"code": "not_found", "message": "No such cinema."}
     },
     FORBIDDEN: dict[str, bool | dict[str, str]] = {
         "ok": False,
         "error": {"code": "forbidden", "message": "You can't do that here."}
     };

def refused(code: str, message: str) -> dict[str, bool | dict[str, str]] {
    return {"ok": False, "error": {"code": code, "message": message}};
}
