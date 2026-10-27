# JI-061: A nested tuple in a client comprehension loses its names

- **Version:** Jac 0.38.0
- **Found:** 2026-10-27, building the Reports donut (feat/report-charts).
- **Status:** open; worked around with dicts instead of tuples.

## Reproduction

In a client (`.jac` under `web/`) component:

```jac
slices = [("Rafiki", 1000, "red"), ("Other", 200, "grey")];
items = [<li key={f"{i}"}>{name}</li> for (i, (name, cents, colour)) in enumerate(slices)];
```

`jac check` passes. `jac build web` fails at the client audit:

```
error[E5101]: Client codegen emitted 'name', which the module never binds
  --> web/backoffice/report_charts.jac:235:42
```

The generated JavaScript destructures only the outer pair `(i, …)` and drops the
inner tuple's names, so `name`, `cents` and `colour` are free identifiers. Without
the build's audit, the page would load and then throw a `ReferenceError`.

## Expected versus actual

Expected: nested tuple targets in a comprehension bind every name, as in Python.
Actual: the inner names aren't emitted, in client code only. `jac check` doesn't flag
it; the build does.

## Workaround

Iterate over a list of dicts (`for m in slices`, reading `m["name"]`), with any index
kept in the dict. No tuple unpacking in client comprehensions.

## Suggested fix

Lower nested tuple targets in client comprehensions to nested array destructuring
(`([i, [name, cents, colour]]) => …`), and have `jac check` run the same free-name
audit as the build.
