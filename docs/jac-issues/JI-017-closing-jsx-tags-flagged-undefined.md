# JI-017: `jac check` flags every closing HTML tag in JSX as an undefined name (W2001)

- **Version:** jaclang 0.37.18
- **Found:** 2026-09-27, P0.8b
- **Status:** open (checker false positive; code builds and runs correctly)

## Behaviour
Every closing *intrinsic* (lower-case HTML) tag produces `W2001 Name '<tag>' may be undefined`, pointing
at the closing tag. Opening tags and component tags (`</Card>`) are not flagged. Minimal repro (`jac check file.jac`):
```jac
def:pub TextOnly -> JsxElement { return <div>hello</div>; }              # W2001 'div' (col of </div>)
def:pub Nested -> JsxElement { return <main><section>hi</section></main>; } # W2001 'section', 'main'
```
It happens in isolated file checks and in workspace checks (`jac check`, per app), and it is also the
source of the `W2001 'div'`/`'button'` warnings in freshly scaffolded projects (JI-009).

## Impact
Warning counts grow with every screen built, which drowns real `W2001` findings and breaks
warning-count ratchets.

## Workaround (in place)
`scripts/count_warnings.sh` (used by `scripts/check_warnings.sh`) discounts **only** `W2001` warnings
whose name is a standard HTML element. `scripts/hooks_selftest.sh` checks that a genuinely undefined
name is still counted.

## Possible improvement (suggestion)
Treat closing intrinsic tag names like opening ones (no name resolution) in the checker.
