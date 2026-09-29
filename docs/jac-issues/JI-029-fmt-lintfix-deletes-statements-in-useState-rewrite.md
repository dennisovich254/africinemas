# JI-029: `jac fmt --lintfix` deletes statements when it rewrites `useState` to `has`

- **Version:** jaclang 0.37.18
- **Found:** 2026-09-28, P2.7b (the pre-commit format check says to run `jac fmt --lintfix <file>`; doing so emptied the sign-in form's validation)
- **Status:** open (we run plain `jac fmt`, never `--lintfix`)

## Reproduction (`jac fmt --lintfix page.jac`)
```jac
import from react { useState }

def:pub Form -> JsxElement {
    [error, set_error] = useState("");
    def submit(text: str) {
        if not text {
            set_error("Enter some text.");
            return;
        }
        set_error("");
    }
    return <input value={error} onChange={lambda (e: any) { submit(e.target.value); }}/>;
}
```
After `--lintfix`:
```jac
def:pub Form -> JsxElement {
    has error: str = "";
    def submit(text: str) {
        if not text { }
        error = "";
    }
    ...
}
```
The `useState` pair becomes a `has` field, as the lint rule intends. But inside the `if`, both the setter call and the `return` are deleted, so the function now carries on and clears the error it should have shown. The setter call outside the `if` is converted correctly (`error = "";`).

On our real files it also left setters passed as props (`on_change={set_email}`) pointing at names that no longer exist, and typed a `useState(None)` field as `has access: None`. `jac check` caught those two, but not the deleted statements.

## Why it matters
`jac fmt --check` fails with `jac fmt --lintfix <file>` as the suggested fix, so this is the command people will run. It changes behaviour silently, and in our case removed input validation.

## Workaround (in place)
Run plain `jac fmt <files>`: it satisfies `jac fmt --check` here and changes only layout. Review any `--lintfix` diff before keeping it.
