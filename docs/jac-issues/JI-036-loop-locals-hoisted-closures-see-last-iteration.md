# JI-036: In client code, locals assigned in a `for` loop are hoisted, so closures see the last iteration

- **Version:** jaclang 0.37.18
- **Found:** 2026-10-02, P4.6 (on the seat map, tapping a seat chose the wrong one, and the arrow keys moved from the wrong seat)
- **Status:** open. Confirmed in the compiled bundle (`.jac/client/web/compiled/web/storefront/SeatMap.js`).

## Reproduction
```jac
for s in seats {
    seat: dict[str, any] = s;
    cells.append(<button onClick={lambda { choose(seat); }}>{seat["label"]}</button>);
}
```
It compiles to:
```js
let seat;                       // declared once, at the top of the function
for (const s of seats) {
    seat = s;                   // reassigned on every pass
    cells.push(__jacJsx("button", {"onClick": () => choose(seat)}, ...));
}
```
Every handler closes over the one `seat` variable, so after the loop they all see the last seat. `jac check` is clean, and the page renders correctly; only the handlers are wrong.

## Why it matters
In Python, closures over a loop variable see the last value too, but there each element is usually handled through a comprehension or a function. In the client this pattern is the natural way to build a list of elements with handlers, and the failure is silent.

## Workaround (in place)
Build such elements with a comprehension (`[<X .../> for s in seats]`, which compiles to `.map` with a parameter per element) or a separate component that receives the item as a prop, as `SeatButton` in `web/storefront/SeatMap.jac` does.

## Suggested fix
Declare locals first assigned inside a loop body with `let` inside the loop block (block scope), so each pass gets its own binding, as JavaScript's `for (const …)` already does for the loop variable.
