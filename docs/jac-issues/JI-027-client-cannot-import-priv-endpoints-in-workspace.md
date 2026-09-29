# JI-027: In a workspace with `[apps.*]` tables, importing a `def:priv` endpoint into client code needs a module pin the auth guide doesn't mention (E5082)

- **Version:** jaclang 0.37.18
- **Found:** 2026-09-28, P2.7b (the web UI calling `end_shift`, `my_access` and the other staff endpoints)
- **Status:** open, docs (resolved here with a documented `[placement.pins]` entry)

## Reproduction (`jac check helpers.jac`)
```jac
# srv.jac -- server-anchored (a Python import, root access)
import os;
def:priv secret_dict(tenant: str) -> dict[str, any] { return {"n": len([root-->]) + len(os.sep)}; }
def:pub open_dict(tenant: str) -> dict[str, any] { return {"n": len([root-->]) + len(os.sep)}; }
```
```jac
# helpers.jac -- client code (it imports from "@jac/runtime")
import from "@jac/runtime" { jacLogout }
import from srv { secret_dict }

async def sign_out() {
    await secret_dict("x");
    jacLogout();
}
```
What we saw:

| `jac.toml` | import of `def:priv` | import of `def:pub` |
|---|---|---|
| `[project]` only | passes | passes |
| with `[apps.web] kind = "web-app"` (with or without other apps) | **E5082** "has no client-side presence" | passes |

| with `[apps.web]` and `[placement.pins] "srv" = "server"` | passes | passes |

Naming the endpoint in the entry module's import list doesn't change the result; the pin does.

## Why it matters
`jac guide jac-cl-auth` shows client code importing and awaiting a `def:priv` server function (`save_profile`) with no pin. In a workspace that fails with E5082, whose help text suggests making the endpoint `def:pub` (which also accepts anonymous callers, per `jac guide jac-sv-endpoints`) or moving it to the client. Neither fits a login-required endpoint. The fix is in `jac guide jac-codespaces` under `[placement.pins]`: a module-level `"server"` pin makes client imports of that module "full service-boundary imports (non-pub items callable with auth)". Neither the auth guide nor the E5082 help points there.

## Workaround (in place)
`jac.toml` pins the endpoint modules the web UI imports (`core.tenancy.signup`, `core.tenancy.tenant_api`) to `"server"`. The endpoints stay `def:priv`.
