"""A choice from a long list that narrows as you type (improvements #12): an input
showing the choice, which on focus opens the list ("Everything" first) and filters it by
what's typed. Arrow keys move through it, Enter picks, Escape closes; a tap or click
picks too. A combobox to assistive technology, each choice an option.
"""

import from react { useState }
import from ...components.ui.label { Label }
import from .form_parts { on_input }

def matches(label: str, text: str) -> bool {
    return text.strip().lower() in label.lower();
}

def:pub SearchSelect(
    field_id: str,
    label: str,
    value: str,
    options: list[tuple[str, str]],
    on_pick: any,  # jac:ignore[W1037] (code) -> None
    all_label: str = "Everything",
    testid: str = ""
) -> JsxElement {
    [open, set_open] = useState(False);
    [text, set_text] = useState("");
    [active, set_active] = useState(0);
    choices: list[tuple[str, str]] = [("", all_label)] + options;
    chosen = (
        [
            name
            for (code, name) in choices
            if code == value
        ]
        + [all_label]
    )[0];
    shown: list[tuple[str, str]] = [
        (code, name)
        for (code, name) in choices
        if matches(name, text)
    ]
        if open
        else [];
    list_id = f"{field_id}-list";

    def pick(code: str) {
        on_pick(code);
        set_open(False);
        set_text("");
    }

    def start {
        set_open(True);
        set_text("");
        set_active(0);
    }

    def typed(words: str) {
        set_text(words);
        set_open(True);
        set_active(0);
    }

    def key(e: any) {  # jac:ignore[W1037]
        if e.key == "ArrowDown" {
            e.preventDefault();
            if not open {
                start();
            } else {
                set_active(min(active + 1, len(shown) - 1));
            }
        } elif e.key == "ArrowUp" {
            e.preventDefault();
            set_active(max(active - 1, 0));
        } elif e.key == "Enter" {
            if open and len(shown) > 0 {
                e.preventDefault();
                pick(shown[min(active, len(shown) - 1)][0]);
            }
        } elif e.key == "Escape" {
            set_open(False);
            set_text("");
        }
    }

    def keep_focus(e: any) {  # jac:ignore[W1037]
        # A press on the list keeps the input focused, so its blur doesn't close the
        # list before the click lands.
        e.preventDefault();
    }

    return
        <div className="relative flex w-full flex-col gap-1.5 sm:w-72">
            <Label htmlFor={field_id}>{label}</Label>
            <input
                id={field_id}
                data-testid={testid or None}
                role="combobox"
                aria-expanded={"true" if open else "false"}
                aria-controls={list_id}
                aria-autocomplete="list"
                aria-activedescendant={f"{field_id}-option-{active}"
                    if open and len(shown) > 0
                    else None}
                autoComplete="off"
                value={text if open else chosen}
                placeholder={chosen if open else ""}
                onFocus={start}
                onClick={start}
                onBlur={lambda { set_open(False); }}
                onKeyDown={key}
                onChange={on_input(typed)}
                className="min-h-11 w-full rounded-md border border-input bg-background px-3 text-sm"
            />
            {open
                and <ul
                    id={list_id}
                    role="listbox"
                    aria-label={label}
                    onMouseDown={keep_focus}
                    className="absolute top-full z-30 mt-1 max-h-72 w-full overflow-y-auto rounded-md border bg-popover p-1 text-popover-foreground shadow-md"
                >
                    {len(shown) == 0
                        and <li className="px-3 py-2 text-sm text-muted-foreground">
                            Nothing matches
                        </li>}{[
                        <li
                            key={c[0] or "all"}
                            id={f"{field_id}-option-{n}"}
                            role="option"
                            aria-selected={"true" if c[0] == value else "false"}
                            onClick={lambda { pick(c[0]); }}
                            onMouseEnter={lambda { set_active(n); }}
                            className={"flex min-h-11 cursor-pointer items-center rounded-sm px-3 text-sm "
                                + (
                                    "bg-accent text-accent-foreground"
                                        if n == active
                                        else ""
                                )
                                + (" font-semibold" if c[0] == value else "")}
                        >
                            {c[1]}
                        </li> for (n, c) in enumerate(shown)
                    ]}
                </ul>}
        </div>;
}
