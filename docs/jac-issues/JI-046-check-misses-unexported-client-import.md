# JI-046: `jac check` passes a client import of a non-`:pub` function that the client compiler rejects

- **Version:** jaclang 0.37.18
- **Found:** 2026-10-10, P8.6c (`jac run --dev main.jac`)
- **Status:** open (made the function `def:pub`)

## What we saw
`web/storefront/customer_session.jac` (client code) imported `remember_email` from `web/auth/session.jac`, where it was a plain `def`. `jac check` on both files passed with no error or warning. Starting the app failed while compiling the client:

```
✖ Error: Error loading main.jac: /home/denis/africinemas/web/storefront/customer_session.jac: runtime import(s) remember_email are not exported by /home/denis/africinemas/web/auth/session.jac. Use :pub for runtime values; annotation-only references must not produce runtime imports.
```

## Workaround (in place)
Mark any function that another client module imports `def:pub`.

## Suggestion upstream
Have `jac check` report the same "not exported" error the client compiler raises, so it shows up before a build or a dev server start.
