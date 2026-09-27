# JI-023: The documented `_before_request` middleware walker never runs, and is exposed as a public route

- **Version:** jaclang 0.37.18
- **Found:** 2026-09-27, P1.4 (spike S3: reading the `Host` header to pick the tenant)
- **Status:** open (fallback adopted, ADR-0006)

## Docs
- `jac guide jac-sv-endpoints`: "Underscore-prefixed *walkers* are NOT inert: they become middleware hooks (`_before_request`, `_authenticate`) that run around every request."
- `jac guide reference/plugins/jac-scale-http`, "Middleware Walkers": `walker _before_request { has request: dict; can log with Root entry { ... } }`, and a similar `_authenticate` that reports a 401.

## Behaviour (real server, `jac run`, a `service` app)
```jac
walker _before_request {
    has request: dict[str, any] = {};      # the docs' bare `dict` fails jac check (E1036)
    can log with Root entry {
        with open(os.environ["S3_HOOK_LOG"], "a") as f { f.write(f"{self.request}\n"); }
    }
}
def:pub s3_hello -> str { return "hi"; }
walker:pub s3_ping { can go with Root entry { report "pong"; } }
def:priv s3_whoami -> str { return str(root.__jac__.id); }
```
- `POST /function/s3_hello` (anonymous, with a custom `Host`), `POST /walker/s3_ping` (anonymous, and with a token) and `POST /function/s3_whoami` (with a token) all return 200. **The hook never runs**: its log file is never created.
- `POST /walker/_before_request` **is routed**, and fails: `{"error": "AttributeError: 'dict' object has no attribute 'state'"}`.
- In the 0.37.18 runtime sources we found no reference to `_before_request` or `_authenticate`. Request middleware is registered with `JacAPIServer.add_middleware`, which only server extensions from installed plugins reach (`Jac.get_server_extensions()`).

Encoded in `tests/spikes/s3_s6_real_server_tests.jac`.

## Impact
- An `_authenticate` hook written from the docs would protect nothing, silently.
- Every underscore walker is an extra public endpoint.
- The documented examples no longer type-check (a bare `dict` requires type arguments).

## Workaround (in place)
- No app code defines underscore walkers; `tests/unit/no_underscore_walkers_tests.jac` guards this.
- The tenant is selected by an explicit parameter, and authorization happens inside each endpoint (ADR-0006).

## Possible improvements (suggestions)
- Wire `_before_request` / `_authenticate` as the guides describe, and keep them off the public route table.
- Or remove the section from the guides, and document `add_middleware` through a plugin as the supported route.
