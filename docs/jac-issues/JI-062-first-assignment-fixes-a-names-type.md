# JI-062: A name's first assignment fixes its type for the whole function

- **Version:** Jac 0.38.0
- **Found:** 2026-10-29, writing the P15.6b integration test
  (tests/integration/reconcile_tests.jac).
- **Status:** open; worked around with a new name.

## Reproduction

```jac
import from datetime { timedelta }

def f -> int {
    left = timedelta(hours=1);
    print(left);
    left = [1, 2];
    return len(left);
}
```

`jac check`:

```
error[E1001]: Cannot assign list[int] to timedelta
  --> rebind.jac:6:5
error[E1053]: Cannot assign timedelta to parameter 'obj' of type Sized
  --> rebind.jac:7:16
```

## Expected versus actual

Expected: as in Python, an unannotated name can be bound again to a value of another
type; the checker follows the new value (or, at most, warns).
Actual: the first assignment's inferred type becomes the name's declared type for the
whole function. A later assignment of another type is an error, and later uses are
still checked against the first type. In a long test function the two assignments can
be a hundred lines apart, so the message points at the second without naming the
first.

## Workaround

Use a new name for the new value.

## Suggested fix

Narrow an unannotated name to the type of its latest assignment, as Pyright does. If
the strict reading is intended, say so in the message: "`left` was inferred as
timedelta at line 4; annotate it, or use a new name".
