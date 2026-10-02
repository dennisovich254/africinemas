# JI-037: In client code, an empty list of unknown type is truthy

- **Version:** jaclang 0.37.18
- **Found:** 2026-10-02, P4.6 (with no seats chosen, the checkout bar said "0 seats:" instead of its prompt)
- **Status:** open. Confirmed in the compiled bundle.

## Reproduction
```jac
[chosen, set_chosen] = useState([]);          # untyped to the checker
text = "some seats" if chosen else "none";   # always "some seats"
```
A value whose type the checker knows as a list compiles through Jac's truthiness helper (`_jac.builtin.bool(seats)`), so an empty list is false, as in Python. A value of unknown type, such as anything from `useState`, compiles to JavaScript's own test, where `[]` (and `{}`) is true. So `if chosen`, `not chosen` and `chosen and …` all behave as though the list were non-empty. `jac check` is clean.

## Why it matters
Silent wrong behaviour: empty-state text never shows, and a button guarded with `disabled={not chosen}` stays enabled with nothing chosen. The same family as JI-035 (`in` on an untyped value).

## Workaround (in place)
Give state values a typed local right after `useState` (`picked: list[str] = chosen;`) and test emptiness with `len(picked) > 0`, as `web/storefront/Checkout.jac` does.

## Suggested fix
Compile truthiness of a value of unknown type through the same runtime helper, so client code follows Python's rules whatever the checker knows.
