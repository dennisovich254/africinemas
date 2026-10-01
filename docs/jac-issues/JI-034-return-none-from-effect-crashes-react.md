# JI-034: In client code, `return None;` from a `useEffect` callback reaches React as `null` and crashes it

- **Version:** jaclang 0.37.18
- **Found:** 2026-10-01, P4.1b-b (the home page editor crashed with "destroy is not a function")
- **Status:** open (worked around; see below)

## Reproduction
```jac
def schedule_preview -> any {
    if page is None {
        return None;          # compiles to `return null;`
    }
    timer: any = win.setTimeout(...);
    return lambda { win.clearTimeout(timer); };
}
useEffect(schedule_preview, [page]);
```

## Why it matters
React accepts only a cleanup function or `undefined` from an effect. Jac's `None` compiles to `null`, so React warns ("useEffect must not return anything besides a function … You returned null") and then throws `TypeError: destroy is not a function` when the effect re-runs or the component unmounts. The whole component tree goes to the error boundary. Python's idiom (`return None` for "nothing") is exactly the wrong one here, and `jac check` is clean even with the effect typed `-> any`.

## Workaround (in place)
Return a do-nothing cleanup on the early path: `return lambda {};` (`web/backoffice/HomePageSection.jac`). A bare `return;` would also work, but a typed `-> any` effect then mixes return shapes.

## Suggested fix
Either compile `return None` inside a function passed to `useEffect` as `return undefined`, or have the client checker warn when a hook callback can return `None`.
