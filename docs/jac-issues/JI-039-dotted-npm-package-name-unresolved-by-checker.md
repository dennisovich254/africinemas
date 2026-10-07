# JI-039: `jac check` can't resolve an npm package whose name contains a dot (`qrcode.react`)

- **Version:** jaclang 0.37.18
- **Found:** 2026-10-07, P6.1 (ticket QR codes on the booked panel)
- **Status:** open. **Low:** warnings only; the build and the browser use the package correctly (e2e green).

## What happened
`import from "qrcode.react" { QRCodeSVG }` gives `W1101 Cannot import name 'QRCodeSVG' from module 'qrcode.react'`, and every use of `QRCodeSVG` gives `W1051 Expression type could not be resolved`. The package is installed in `.jac/client/node_modules/qrcode.react/` with its own types (`"types": "./lib/index.d.ts"`).

The checker seems to read the dot as a module separator (`qrcode` / `react`):
- an undotted scoped package in the same file (`@hugeicons/react`) resolves;
- the subpath `"qrcode.react/lib/index.js"` resolves too.

The subpath isn't a workaround, though: the package's `exports` map only lists `.`, so Vite refuses the subpath import.

Other installed packages with a dot in their name: `lodash.debounce`, `lodash.throttle`.

## Expected
String-path npm imports are package names (`jac guide jac-npm-packages`). A dot is legal in npm names and should resolve like any other name, using the package's types.

## Workaround (in place)
Keep the import as it is and suppress the two false positives where they occur: `# jac:ignore[W1101]` on the import, and `# jac:ignore[W1051]` on the JSX tag (`web/storefront/PayPanel.jac`).
