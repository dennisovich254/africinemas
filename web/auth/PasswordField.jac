"""A labelled password input with a show/hide toggle.

The toggle is a toggle button (aria-pressed) with a constant name, pointing at the
input it controls, so screen readers announce "Show password, toggle button, pressed".
"""

import from react { useState }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { ViewIcon, ViewOffSlashIcon }
import from ...components.ui.field { Field, FieldLabel, FieldDescription }
import from ...components.ui.input_group {
    InputGroup,
    InputGroupInput,
    InputGroupAddon,
    InputGroupButton
}

# `on_change` receives the new value (a string).
def:pub PasswordField(
    id: str,
    label: str,
    value: str,
    on_change: any,  # jac:ignore[W1037]
    auto_complete: str,
    hint: str = "",
    min_length: int = 0
) -> JsxElement {
    [shown, set_shown] = useState(False);
    hint_id = f"{id}-hint";
    return
        <Field>
            <FieldLabel htmlFor={id}>{label}</FieldLabel>
            <InputGroup className="h-11">
                <InputGroupInput
                    id={id}
                    name={id}
                    type={"text" if shown else "password"}
                    value={value}
                    onChange={lambda (e: any) { on_change(e.target.value); }}  # jac:ignore[W1037]
                    autoComplete={auto_complete}
                    minLength={min_length if min_length else None}
                    required={True}
                    aria-describedby={hint_id if hint else None}
                    className="h-11 text-base"
                />
                <InputGroupAddon align="inline-end">
                    <InputGroupButton
                        size="icon-sm"
                        className="size-11"
                        aria-label="Show password"
                        aria-pressed={"true" if shown else "false"}
                        aria-controls={id}
                        onClick={lambda { set_shown(not shown); }}
                    >
                        <HugeiconsIcon
                            icon={ViewOffSlashIcon if shown else ViewIcon}
                            strokeWidth={2}
                            aria-hidden="true"
                        />
                    </InputGroupButton>
                </InputGroupAddon>
            </InputGroup>
            {hint and <FieldDescription id={hint_id}>{hint}</FieldDescription>}
        </Field>;
}
