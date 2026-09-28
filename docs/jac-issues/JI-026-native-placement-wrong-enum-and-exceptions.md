# JI-026: In a module Jac compiles natively by default, an enum return becomes an int and a custom exception loses its type

- **Version:** jaclang 0.37.18
- **Found:** 2026-09-28, P2.1 (`Tenant.move_to` refused a transition with an exception `except InvalidTransition` didn't catch)
- **Status:** open (worked around project-wide)

## Reproduction (`jac run probe.jac`, no `jac.toml`)
```jac
# rules.jac -- no Python imports, so the default placement compiles it natively
enum Color { RED = "red", BLUE = "blue" }
glob NEXT: dict[Color, set[Color]] = {Color.RED: {Color.BLUE}, Color.BLUE: set()};
class BadMove(ValueError) {}

def move(current: Color, target: Color) -> Color {
    if target not in NEXT[current] {
        raise BadMove(f"can't go from {current.value} to {target.value}");
    }
    return target;
}
```
```jac
# probe.jac
import from rules { Color, BadMove, move }
with entry {
    try {
        print(f"red->blue: {move(Color.RED, Color.BLUE)}");
        move(Color.BLUE, Color.RED);
    } except BadMove as e { print(f"BadMove: {e}"); }
      except Exception as e { print(f"OTHER {type(e)!r} {e!r}"); }
}
```
Output with the default placement:
```
red->blue: 1                         # expected Color.BLUE
OTHER '' 'key not found'             # expected BadMove, not caught by `except BadMove`
```
With `[placement] default = "server"` in `jac.toml`:
```
red->blue: Color.BLUE
BadMove: can't go from blue to red
```

## Why it happens (per the docs)
`jac guide jac-codespaces`, rule 5: "Whole anchor-free modules prefer native." A module with no Python imports, endpoints, JSX or persistence is compiled with LLVM. Nothing warns that its enum and exception semantics then differ from Python's.

## Impact
Silent wrong values (an `int` where an enum was returned), and error handling that doesn't fire, in ordinary pure-logic modules such as state machines or validators.

## Workaround (in place)
`jac.toml`: `[placement] default = "server"`. AfriCinemas has no use for native code.

## Possible improvement (suggestion)
Keep Python semantics for enums and exceptions across the native boundary. Or don't infer native placement for modules that use them, or at least warn when a module is placed native implicitly.
