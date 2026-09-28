# JI-030: In client code, a local variable named `type` compiles to the builtin `type`

- **Version:** jaclang 0.37.18
- **Found:** 2026-09-28, P2.7b (the password field's show/hide button submitted the sign-in form)
- **Status:** open (worked around by renaming the variable)

## What we saw
The shadcn `InputGroupButton` (`components/ui/input_group.jac`) does:
```jac
def:pub InputGroupButton(props: any) -> JsxElement {
    type = props["type"] or "button";
    ...
    <Button {**props} type={type} ...>
```
The compiled bundle (`.jac/client/web/compiled/components/ui/input_group.js`) declares the local, then reads the builtin instead:
```js
let type = (props["type"] || "button");
...
Object.assign({}, props, {"type": _jac.types.type}, ...)
```
React drops the function-valued `type` attribute. A `<button>` with no `type` inside a `<form>` is a submit button, so clicking the eye icon submitted the form. `jac check` is clean.

We have seen this with the name `type` only. We haven't tested other builtin names used as locals (`id`, `list`, `str`, ...).

## Why it matters
A silent wrong value in generated UI code, found only by clicking. It's in a vendored shadcn component, so any project that installs `input-group` has it.

## Workaround (in place)
Rename the local (`button_type`). The e2e test "the password field can be shown and hidden" now asserts the toggle's `type="button"` and that clicking it doesn't submit.
