# JI-040: A space inside an f-string format spec is dropped, by the compiler and by `jac fmt`

- **Version:** jaclang 0.37.18
- **Found:** 2026-10-07, P6.3 (the ticket email's showtime line)
- **Status:** open. **Medium:** silently wrong text; `jac check` is clean.

## What happened
In Python, a format spec is passed to `__format__` as written, spaces included: `f"{d:%B %Y}"` gives `October 2026`. Jac drops the space:

```jac
import from datetime { datetime }
with entry {
    d = datetime(2026, 10, 9, 18, 15);
    print(repr(f"{d:%B %Y}"));          # 'October2026'  (Python: 'October 2026')
    print(repr(f"{d:%H %M}"));          # '1815'         (Python: '18 15')
    print(repr(f"{d.strftime('%B %Y')}")); # 'October 2026'
}
```

`jac fmt` also rewrites the source: `{local:%B %Y}` becomes `{local:%B%Y}`, so the space is lost from the file too, not only from the output.

Format specs without spaces are unaffected (`f"{3.14159:>10.2f}"` gives `'      3.14'`).

## Expected
The format spec is the text between `:` and `}`, as in Python, and both the compiler and the formatter keep it unchanged.

## Workaround (in place)
Format dates with `strftime` inside the braces rather than a spec, e.g. `f"{local.strftime('%B %Y, %H:%M')}"` (`core/notify/ticket_mail.jac`).
