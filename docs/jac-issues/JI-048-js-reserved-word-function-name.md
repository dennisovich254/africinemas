# JI-048: A client function named `export` passes `jac check`, then breaks the Vite build

- **Version:** jaclang 0.37.18
- **Found:** 2026-10-11, P12.5 (`jac run --no-dev main.jac`)
- **Status:** open (renamed ours to `export_catalog`)

## What we saw
`web/backoffice/SnackImportPage.jac` (client code) had a nested `async def export { ... }`. `jac check` and `jac fmt` passed. Starting the app failed in the client build:

```
web/compiled/web/backoffice/SnackImportPage.js (141:14): Expected ident
```

The compiler emitted `async function export() { ... }`. `export` is a reserved word in JavaScript, so Rollup refused the module. The error pointed at an unrelated line in Jac's string helpers (`index(s, sub, ...)`), not at the function.

## Workaround (in place)
Don't name a client function or variable after a JavaScript reserved word (`export`, `import`, `delete`, `new`, `default`, `function`, `var`, `let`, `const`, `enum`, ...). Ours is `export_catalog`.

## Suggestion upstream
Have the client compiler rename identifiers that clash with JavaScript reserved words (as it already does for Jac keywords via the backtick escape), or have `jac check` report them in client code.
