"""`/app/new`: create a cinema in two steps (P2.7b).

1. Name and web address. The address is suggested from the name and checked with the
   server (`check_slug`) when the field loses focus, so problems show before submitting.
2. "Brand your cinema": reserved for the branding tools (plan 3.8, 8.5) and skippable;
   skipping keeps the AfriCinemas default theme.
"""

import from react { useState, useRef }
import from "@jac/runtime" { Link }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { CheckmarkCircle02Icon, AlertCircleIcon }
import from ...components.ui.button { Button }
import from ...components.ui.card { Card, CardContent }
import from ...components.ui.field {
    FieldGroup,
    Field,
    FieldLabel,
    FieldDescription,
    FieldError
}
import from ...components.ui.input { Input }
import from ...components.ui.input_group {
    InputGroup,
    InputGroupInput,
    InputGroupAddon,
    InputGroupText
}
import from ...components.ui.spinner { Spinner }
import from core.tenancy.signup { check_slug, create_cinema }  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)
import from .nav { web_address, suggest_slug }
import from .PlainLayout { PlainLayout, AccountActions }

glob STEPS: list[str] = ["Name your cinema", "Brand your cinema"];

def Progress(step: int) -> JsxElement {
    return
        <ol aria-label="Progress" className="flex gap-2 text-sm">
            {[
                <li
                    key={label}
                    aria-current={"step" if i + 1 == step else None}
                    className={"flex flex-1 items-center gap-2 border-t-2 pt-2 "
                        + (
                            "border-primary font-medium text-foreground"
                                if i + 1 <= step
                                else "border-border text-muted-foreground"
                        )}
                >
                    <span>{i + 1}</span>
                    <span>{label}</span>
                </li> for (i, label) in enumerate(STEPS)
            ]}
        </ol>;
}

# The address check's outcome, under the field. `state` is "", "checking", "ok" or "bad".
def SlugStatus(state: str, message: str) -> JsxElement {
    icon: any = None;  # jac:ignore[W1037]
    tone = "text-muted-foreground";
    if state == "ok" {
        icon = <HugeiconsIcon
            icon={CheckmarkCircle02Icon}
            strokeWidth={2}
            aria-hidden="true"
            className="size-4 shrink-0"
        />;
        tone = "text-foreground";
    } elif state == "bad" {
        icon = <HugeiconsIcon
            icon={AlertCircleIcon}
            strokeWidth={2}
            aria-hidden="true"
            className="size-4 shrink-0"
        />;
        tone = "text-destructive";
    } elif state == "checking" {
        icon = <Spinner aria-hidden="true"/>;
    }
    return
        <p
            id="cinema-slug-status"
            aria-live="polite"
            className={f"flex min-h-5 items-center gap-2 text-sm {tone}"}
        >
            {icon}{message}
        </p>;
}

def:pub NewCinemaWizard -> JsxElement {
    [step, set_step] = useState(1);
    [name, set_name] = useState("");
    [slug, set_slug] = useState("");
    [slug_edited, set_slug_edited] = useState(False);
    [slug_state, set_slug_state] = useState("");
    [slug_message, set_slug_message] = useState("");
    [name_error, set_name_error] = useState("");
    [busy, set_busy] = useState(False);
    [created, set_created] = useState("");
    [failed, set_failed] = useState("");
    slug_input = useRef(None);
    # The address most recently sent to check_slug; older answers are ignored.
    last_checked = useRef("");
    name_input = useRef(None);

    def show_slug(state: str, message: str) {
        set_slug_state(state);
        # Server messages say "slug"; owners know it as the web address.
        set_slug_message(message.replace("slug", "web address"));
    }

    # Asks the server about `wanted`; returns True if it's valid and free.
    async def verify(wanted: str) -> bool {
        answer: any = None;  # jac:ignore[W1037]
        if not wanted.strip() {
            show_slug("", "");
            return False;
        }
        show_slug("checking", "Checking…");
        last_checked.current = wanted;
        try {
            answer = await check_slug(wanted);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("check_slug failed", e);
            show_slug("", "");
            return True;  # let the server decide on submit
        }
        if last_checked.current != wanted {
            return False;  # a newer check is under way
        }
        if answer["available"] {
            show_slug("ok", f"{web_address(answer['slug'])} is available.");
            return True;
        }
        show_slug("bad", answer["message"]);
        return False;
    }

    def on_name(value: str) {
        set_name(value);
        set_name_error("");
        if not slug_edited {
            set_slug(suggest_slug(value));
            show_slug("", "");
        }
    }

    def on_slug(value: str) {
        set_slug(value);
        set_slug_edited(True);
        show_slug("", "");
    }

    async def submit(e: any) {  # jac:ignore[W1037]
        e.preventDefault();
        result: any = None;  # jac:ignore[W1037]
        set_failed("");
        if not name.strip() {
            set_name_error("Enter your cinema's name.");
            name_input.current.focus();
            return;
        }
        set_busy(True);
        try {
            result = await create_cinema(name, slug);  # jac:ignore[W2037]
        } except Exception as err {
            console.warn("create_cinema failed", err);
            set_busy(False);
            set_failed(
                "We couldn't create your cinema. Check your connection and try again."
            );
            return;
        }
        set_busy(False);
        if result["created"] {
            set_created(result["slug"]);
            set_step(2);
            return;
        }
        code = result["error"]["code"];
        if code == "invalid_name" {
            set_name_error(result["error"]["message"]);
            name_input.current.focus();
        } else {
            show_slug("bad", result["error"]["message"]);
            slug_input.current.focus();
        }
    }

    body: any = None;  # jac:ignore[W1037]
    if step == 1 {
        slug_bad = slug_state == "bad";
        body = <form onSubmit={submit} noValidate={True}>
            <FieldGroup>
                <h2 className="text-lg font-semibold">{STEPS[0]}</h2>
                {failed and <FieldError>{failed}</FieldError>}
                <Field data-invalid={"true" if name_error else None}>
                    <FieldLabel htmlFor="cinema-name">Cinema name</FieldLabel>
                    <Input
                        id="cinema-name"
                        name="cinema-name"
                        ref={name_input}
                        autoComplete="organization"
                        required={True}
                        maxLength={80}
                        value={name}
                        onChange={lambda (ev: any) { on_name(ev.target.value); }}  # jac:ignore[W1037]
                        onBlur={lambda { if not slug_edited { verify(slug); }}}
                        aria-invalid={"true" if name_error else None}
                        aria-describedby={"cinema-name-error" if name_error else None}
                        className="h-11 text-base"
                    />
                    {name_error
                        and <FieldError id="cinema-name-error">
                            {name_error}
                        </FieldError>}
                </Field>
                <Field data-invalid={"true" if slug_bad else None}>
                    <FieldLabel htmlFor="cinema-slug">Web address</FieldLabel>
                    <InputGroup className="h-11">
                        <InputGroupInput
                            id="cinema-slug"
                            name="cinema-slug"
                            ref={slug_input}
                            autoComplete="off"
                            autoCapitalize="none"
                            spellCheck={False}
                            required={True}
                            maxLength={40}
                            value={slug}
                            onChange={lambda (ev: any) { on_slug(ev.target.value); }}  # jac:ignore[W1037]
                            onBlur={lambda { verify(slug); }}
                            aria-invalid={"true" if slug_bad else None}
                            aria-describedby="cinema-slug-hint cinema-slug-status"
                            className="h-11 text-base"
                        />
                        <InputGroupAddon align="inline-end">
                            <InputGroupText>{web_address("")}</InputGroupText>
                        </InputGroupAddon>
                    </InputGroup>
                    <FieldDescription id="cinema-slug-hint">
                        Where customers book: 3 to 40 letters, numbers or hyphens.
                    </FieldDescription>
                    <SlugStatus state={slug_state} message={slug_message}/>
                </Field>
                <Button
                    type="submit"
                    disabled={busy}
                    className="h-11 w-full sm:w-auto sm:self-end sm:px-6"
                >
                    {busy and <Spinner aria-hidden="true"/>}{"Creating…"
                        if busy
                        else "Create cinema"}
                </Button>
            </FieldGroup>
        </form>;
    } else {
        body = <div className="flex flex-col gap-4">
            <h2 className="text-lg font-semibold">{STEPS[1]}</h2>
            <p className="text-muted-foreground">
                Your cinema is ready at{" "}
                <span className="font-medium text-foreground">
                    {web_address(created)}
                </span>
                . Adding your logo and colours comes next; until then your storefront uses the AfriCinemas look. You can brand it any time from Settings.
            </p>
            <Button
                asChild={True}
                className="h-11 w-full sm:w-auto sm:self-end sm:px-6"
            >
                <Link to={f"/app/{created}"}>Skip for now</Link>
            </Button>
        </div>;
    }
    return
        <PlainLayout title="New cinema" account={<AccountActions slugs={[]}/>}>
            <Progress step={step}/>
            <Card>
                <CardContent>{body}</CardContent>
            </Card>
        </PlainLayout>;
}
