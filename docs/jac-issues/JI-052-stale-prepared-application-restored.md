# JI-052: A build can restore an old "prepared application", so a changed client module ships its previous code

- **Version:** jaclang 0.38.0
- **Found:** 2026-10-23, P13.1 (a browser test kept failing after the fix)
- **Status:** open (workaround: move `.jac/cache` aside and rebuild)

## What we saw
We changed one client module, `web/storefront/customer_session.jac`, to stop clearing a value in `localStorage`. The browser test that covers it kept failing. The bundle the server served still had the old code:

```bash
$ grep -n 'remember_email' .jac/client/web/compiled/web/storefront/customer_session.js
4:import { safe_next, remember_email } from "../auth/session.js";
49:  remember_email("");
```

The source no longer had either line. Compiling the file on its own gave the right output:

```bash
$ jac tool jac2js web/storefront/customer_session.jac | grep -c remember_email
0
```

The server log of each failing run began with `Restoring prepared application`. These attempts didn't help:

| Tried | Result |
| --- | --- |
| Deleting the stale `compiled/.../customer_session.js` | Rewritten with the old code on the next build |
| Moving `.jac/cache/applications/` aside | Rebuilt, still the old code |
| Removing the module's `.jir` files from `.jac/cache/<hash>/` | Still the old code |
| `jac run --no-dev --no-cache` | Still `Restoring prepared application`, still the old code |

Only moving the whole `.jac/cache/` aside fixed it. The next build ran a full kernel compile (about 3 minutes) and served the new code.

## Why it matters
A fix can look broken. Worse, a test can pass or fail against code that's no longer in the source, and production could ship an old client module. We may also have hit this earlier, when fixes "didn't show" on the owner's dev server.

## Workaround (in place)
If a page behaves the way the source no longer does, grep the compiled module under `.jac/client/web/compiled/`. If it's stale, stop the server, move `.jac/cache` out of the project and start again.

## Not yet known
- What the prepared application's cache key misses. In `jaclang/compiler/driver/application.jac`, `_prepare_revision` compares a key and dependency digests. The changed module may have been missing from `dependencies`, or the module-level `.jir` cache under `~/.cache/jac/jir/` may have supplied the old unit.
- A minimal repro project. The owner's dev server was running from the same tree during the edit, so the two processes may have shared the cache.

## Suggestion upstream
Make `--no-cache` skip "Restoring prepared application" too, and include every client module's source digest in the prepared application's key.
