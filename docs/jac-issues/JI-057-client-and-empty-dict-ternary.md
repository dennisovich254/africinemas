# JI-057: An empty dict returned by `and` selects the true branch of a client conditional

- **Version:** Jac 0.38.0
- **Found:** 2026-10-25, investigating the snacks-only box office's `KES NaN.NaN` total.
- **Status:** open; verified in the existing generated JavaScript and its runtime.

## Reproduction

```jac
cost: dict[str, any] = {};
total: int = cost["total_cents"] if cost and cost["ok"] else 0;
```

The application's generated client JavaScript contains:

```js
let total = (_jac.poly.and_(cost, () => cost["ok"]) ? cost["total_cents"] : 0);
```

The runtime implements `and_` as:

```js
return _jac.builtin.bool(a) ? bf() : a;
```

With an empty plain object, the helper correctly returns that object, following
Python-style operand-returning `and`. The JavaScript conditional then treats the
returned object as true and reads the absent `total_cents` property.

## Expected versus actual

Expected: `total` is zero for an empty dictionary.
Actual: `total` is `undefined`, and the money formatter displays `KES NaN.NaN`.
The original expression was reproduced with Node using the generated Jac prelude
and expression in the same VM context. Type checking does not catch the problem.

Unlike JI-037's untyped collection test, this case uses a typed dictionary and the
Jac boolean helper; the mismatch occurs when its returned operand is consumed by
a native JavaScript conditional.

## Workaround

Keep the absent pricing response as `None` and test `cost is not None` explicitly
before checking `cost["ok"]`. The empty cart then takes the zero-total branch.
The existing browser sale test now checks `KES 0` and a disabled payment button
both before adding snacks and after starting a new sale. Browser execution is
left to CI; local type and formatting checks passed.

## Suggested fix

Apply Jac truthiness when consuming operand-returning boolean expressions as
conditions, including conditional expressions, so empty collections remain false.
