# JI-053: `jac fmt` wraps a long line and leaves its `# jac:ignore[...]` on the second line, where it no longer applies

- **Version:** jaclang 0.38.0
- **Found:** 2026-10-23, P13.2 (CI's warning ratchet failed after a format)
- **Status:** open (keep ignored lines short enough not to wrap)

## Repro

```jac
def pick(shown: dict[str, any] | None) -> dict[str, any] {  # jac:ignore[W1037]
    found: dict[str, any] = shown or {"cinemas": [], "total": 0, "page": 1, "pages": 1, "states": []};  # jac:ignore[W1037]
    return found;
}
```

Before `jac fmt`, `jac check repro.jac` reports no W1037. Then `jac fmt repro.jac` gives:

```jac
    found: dict[str, any] = shown
        or {"cinemas": [], "total": 0, "page": 1, "pages": 1, "states": []};  # jac:ignore[W1037]
```

After it, `jac check` reports the warning on the first line, `--> repro.jac:2:22` (`dict[str, any]`). The ignore comment now sits on line 3, so it doesn't apply.

## Expected
The formatter keeps a trailing `# jac:ignore[...]` on the line where the statement starts, which is where the checker reports. Or the checker applies a statement's ignore comment to the whole statement.

## Workaround (in place)
Split the expression so the line with the annotation stays short:

```jac
    nothing = {"cinemas": [], "total": 0, "page": 1, "pages": 1, "states": []};
    found: dict[str, any] = shown or nothing;  # jac:ignore[W1037]
```

Related: [JI-029](JI-029-fmt-lintfix-deletes-statements-in-useState-rewrite.md) (another `jac fmt` rewrite that changes meaning).
