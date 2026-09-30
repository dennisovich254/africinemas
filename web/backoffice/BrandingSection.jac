"""`/app/:slug/settings`: the cinema's branding (P3.8b), on the 3.8a endpoints.

Owners start from a preset or change colours, fonts, corners and the logo, watching a
live preview of their storefront in light and dark. "Save draft" keeps the changes
private; "Publish" puts them on the storefront (saving first). The server repairs any
colour that would be hard to read and the page lists what it changed. Each publish is a
version; restoring an earlier one asks first, then publishes it again.
"""

import from react { useState, useEffect }
import from ...components.ui.alert { Alert, AlertTitle, AlertDescription }
import from ...components.ui.badge { Badge }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.theming.branding_api {
    get_branding,  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)
    save_theme,  # jac:ignore[W2037]
    upload_logo,  # jac:ignore[W2037]
    remove_logo,  # jac:ignore[W2037]
    publish_theme,  # jac:ignore[W2037]
    rollback_theme  # jac:ignore[W2037]
}
import from .branding_model {
    role_label,
    radius_label,
    key_roles,
    other_roles,
    is_hex,
    with_colour,
    with_field,
    same_theme,
    adjusted_text,
    version_label
}
import from .ThemePreview { ThemePreview }

glob MODES: list[str] = ["light", "dark"],
     SELECT_CLASSES: str = "min-h-11 w-full rounded-md border border-input bg-background px-3 text-sm",
     LOGO_TYPES: str = "image/png,image/jpeg,image/webp";

def published_on(stamp: str) -> str {
    # When a version was published, in the owner's own date format.
    moment: any = new(Date, stamp);  # jac:ignore[W1037,W2001]
    return moment.toLocaleString();
}

def device_mode -> str {
    # Start the editor in the mode the owner's device is using.
    win: any = window;  # jac:ignore[W1037,W2001]
    return "dark"
        if win.matchMedia("(prefers-color-scheme: dark)").matches
        else "light";
}

def field_id(mode: str, role: str) -> str {
    return f"{mode}-{role}";
}

def texts_for(theme: dict[str, any]) -> dict[str, str] {  # jac:ignore[W1037]
    # The hex text boxes' contents for `theme`: one per mode and role.
    texts: dict[str, str] = {};
    for mode in MODES {
        for role in theme[mode] {
            texts[field_id(mode, role)] = theme[mode][role];
        }
    }
    return texts;
}

def read_as_base64(file: any) -> any {  # jac:ignore[W1037]
    # A promise of the file's contents as base64 (no "data:" prefix).
    def run(resolve: any, reject: any) {  # jac:ignore[W1037]
        win: any = window;  # jac:ignore[W1037,W2001]
        reader_class: any = win.FileReader;  # jac:ignore[W1037]
        reader: any = new(reader_class);  # jac:ignore[W1037]
        def done {
            text: str = reader.result;
            resolve(text.split(",")[1]);
        }
        reader.onload = done;
        reader.onerror = reject;
        reader.readAsDataURL(file);
    }
    return new(Promise, run);  # jac:ignore[W2001]
}

def ColourField(  # jac:ignore[W3030] a colour field: its mode, role, values and three handlers
    mode: str,
    role: str,
    value: str,
    text: str,
    error: str,
    on_pick: any,  # jac:ignore[W1037]
    on_type: any,  # jac:ignore[W1037]
    on_leave: any  # jac:ignore[W1037]
) -> JsxElement {
    key = field_id(mode, role);
    return
        <div className="flex flex-col gap-1.5">
            <Label htmlFor={f"hex-{key}"}>{role_label(role)}</Label>
            <div className="flex items-center gap-2">
                <input
                    type="color"
                    id={f"color-{key}"}
                    aria-label={f"{role_label(role)}, colour picker"}
                    value={value.lower()}
                    onChange={lambda (e: any) { on_pick(mode, role, e.target.value); }}  # jac:ignore[W1037]
                    className="size-11 shrink-0 cursor-pointer rounded-md border bg-transparent p-1"
                />
                <Input
                    id={f"hex-{key}"}
                    value={text}
                    spellCheck={False}
                    autoComplete="off"
                    aria-invalid={"true" if error else "false"}
                    aria-describedby={f"hex-{key}-error" if error else None}
                    onChange={lambda (e: any) { on_type(mode, role, e.target.value); }}  # jac:ignore[W1037]
                    onBlur={lambda { on_leave(mode, role); }}
                    className="min-h-11 font-mono uppercase"
                />
            </div>
            {error
                and <p
                    id={f"hex-{key}-error"}
                    role="alert"
                    className="text-sm text-destructive"
                >
                    {error}
                </p>}
        </div>;
}

def PresetCard(
    preset: dict[str, any],  # jac:ignore[W1037]
    checked: bool,
    on_choose: any  # jac:ignore[W1037]
) -> JsxElement {
    swatches = ["background", "surface", "accent", "ink"];
    return
        <label
            className="flex min-h-11 cursor-pointer flex-col gap-2 rounded-lg border bg-card p-3 has-[:checked]:border-primary has-[:checked]:bg-muted has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-ring"
        >
            <input
                type="radio"
                name="preset"
                value={preset["name"]}
                checked={checked}
                onChange={lambda { on_choose(preset); }}
                className="sr-only"
            />
            <span className="font-medium">{preset["name"]}</span>
            <span className="flex gap-1" aria-hidden="true">
                {[
                    <span
                        key={f"{mode}-{role}"}
                        className="size-5 rounded border"
                        style={{"background": preset[mode][role]}}
                    ></span> for mode in MODES for role in swatches
                ]}
            </span>
        </label>;
}

def:pub BrandingSection(slug: str, cinema: str = "") -> JsxElement {
    [data, set_data] = useState(None);
    [failed, set_failed] = useState("");
    [theme, set_theme] = useState(None);
    [saved, set_saved] = useState(None);
    [texts, set_texts] = useState({});
    [errors, set_errors] = useState({});
    [logo, set_logo] = useState("");
    [mode, set_mode] = useState(device_mode());
    [busy, set_busy] = useState("");
    [message, set_message] = useState("");
    [adjusted, set_adjusted] = useState([]);
    [restoring, set_restoring] = useState(0);

    def show(answer: dict[str, any]) {  # jac:ignore[W1037]
        draft: dict[str, any] = answer["branding"]["draft"];  # jac:ignore[W1037]
        set_data(answer);
        set_theme(draft["theme"]);
        set_saved(draft["theme"]);
        set_texts(texts_for(draft["theme"]));
        set_errors({});
        set_logo(draft["logo"]);
    }

    async def load -> bool {
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await get_branding(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("get_branding failed", e);
            set_failed(
                "We couldn't load your branding. Refresh the page to try again."
            );
            return False;
        }
        if not answer["ok"] {
            set_failed(answer["error"]["message"]);
            return False;
        }
        show(answer);
        return True;
    }

    def start_loading {
        load();
    }
    useEffect(start_loading, [slug]);

    if failed {
        return
            <Alert variant="destructive">
                <AlertDescription>{failed}</AlertDescription>
            </Alert>;
    }
    if data is None or theme is None {
        return
            <p role="status" className="flex items-center gap-2 text-muted-foreground">
                <Spinner aria-hidden="true"/>
                Loading your branding…
            </p>;
    }

    info: dict[str, any] = data;  # jac:ignore[W1037]
    current: dict[str, any] = theme;  # jac:ignore[W1037]
    options: dict[str, any] = info["options"];  # jac:ignore[W1037]
    published: dict[str, any] | None = info["branding"]["published"];  # jac:ignore[W1037]
    versions: list[dict[str, any]] = info["branding"]["versions"];  # jac:ignore[W1037]
    field_errors: dict[str, str] = errors;
    field_texts: dict[str, str] = texts;
    unsaved = not same_theme(current, saved);
    invalid = len(Object.keys(field_errors)) > 0;  # jac:ignore[W2001]

    def pick(m: str, role: str, value: str) {
        key = field_id(m, role);
        set_theme(with_colour(current, m, role, value));
        next_texts: dict[str, str] = {};
        for k in field_texts {
            next_texts[k] = field_texts[k];
        }
        next_texts[key] = value.upper();
        set_texts(next_texts);
        next_errors: dict[str, str] = {};
        for k in field_errors {
            if k != key {
                next_errors[k] = field_errors[k];
            }
        }
        set_errors(next_errors);
        set_message("");
    }

    def type_hex(m: str, role: str, value: str) {
        key = field_id(m, role);
        next_texts: dict[str, str] = {};
        for k in field_texts {
            next_texts[k] = field_texts[k];
        }
        next_texts[key] = value;
        set_texts(next_texts);
        if is_hex(value) {
            pick(m, role, value);
        }
    }

    def leave_hex(m: str, role: str) {
        key = field_id(m, role);
        next_errors: dict[str, str] = {};
        for k in field_errors {
            if k != key {
                next_errors[k] = field_errors[k];
            }
        }
        if not is_hex(field_texts[key]) {
            next_errors[key] = "Enter a colour as # and six digits or letters A–F, like #E0A526.";
        }
        set_errors(next_errors);
    }

    def choose_preset(preset: dict[str, any]) {  # jac:ignore[W1037]
        set_theme(preset);
        set_texts(texts_for(preset));
        set_errors({});
        set_message("");
        set_adjusted([]);
    }

    def change_field(field: str, value: str) {
        set_theme(with_field(current, field, value));
        set_message("");
    }

    async def save_draft -> bool {
        answer: any = None;  # jac:ignore[W1037]
        set_busy("saving");
        set_message("");
        set_adjusted([]);
        try {
            answer = await save_theme(slug, current);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("save_theme failed", e);
            set_busy("");
            set_message("We couldn't save. Check your connection and try again.");
            return False;
        }
        set_busy("");
        if not answer["ok"] {
            set_message(answer["error"]["message"]);
            return False;
        }
        set_theme(answer["theme"]);
        set_saved(answer["theme"]);
        set_texts(texts_for(answer["theme"]));
        set_adjusted(answer["adjusted"]);
        set_message("Draft saved. Only you can see it until you publish.");
        return True;
    }

    async def publish {
        answer: any = None;  # jac:ignore[W1037]
        ready = True;
        if unsaved {
            ready = await save_draft();
        }
        if not ready {
            return;
        }
        set_busy("publishing");
        try {
            answer = await publish_theme(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("publish_theme failed", e);
            set_busy("");
            set_message("We couldn't publish. Check your connection and try again.");
            return;
        }
        set_busy("");
        if not answer["ok"] {
            set_message(answer["error"]["message"]);
            return;
        }
        await load();
        set_message(f"Version {answer['version']} is now on your storefront.");
    }

    async def restore(version: int) {
        answer: any = None;  # jac:ignore[W1037]
        set_restoring(0);
        set_busy("restoring");
        set_message("");
        set_adjusted([]);
        try {
            answer = await rollback_theme(slug, version);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("rollback_theme failed", e);
            set_busy("");
            set_message("We couldn't restore that version. Try again.");
            return;
        }
        set_busy("");
        if not answer["ok"] {
            set_message(answer["error"]["message"]);
            return;
        }
        await load();
        set_message(
            f"Version {version} is back on your storefront, as version {answer[
                'version'
            ]}."
        );
    }

    async def choose_logo(e: any) {  # jac:ignore[W1037]
        file: any = e.target.files[0];  # jac:ignore[W1037]
        answer: any = None;  # jac:ignore[W1037]
        if not file {
            return;
        }
        set_busy("logo");
        set_message("");
        try {
            encoded = await read_as_base64(file);
            answer = await upload_logo(slug, file.type, encoded);  # jac:ignore[W2037]
        } except Exception as err {
            console.warn("upload_logo failed", err);
            set_busy("");
            set_message("We couldn't upload that logo. Try again.");
            return;
        }
        e.target.value = "";
        set_busy("");
        if not answer["ok"] {
            set_message(answer["error"]["message"]);
            return;
        }
        refreshed = await get_branding(slug);  # jac:ignore[W2037]
        if refreshed["ok"] {
            set_logo(refreshed["branding"]["draft"]["logo"]);
            set_data(refreshed);
        }
        set_message("Logo added to your draft. Publish to show it on your storefront.");
    }

    async def drop_logo {
        answer: any = None;  # jac:ignore[W1037]
        set_busy("logo");
        try {
            answer = await remove_logo(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("remove_logo failed", e);
        }
        set_busy("");
        if answer and answer["ok"] {
            set_logo("");
            set_message("Logo removed from your draft.");
        } else {
            set_message("We couldn't remove the logo. Try again.");
        }
    }

    status = (
        f"Version {published['version']} is live · {published['theme']['name']}"
            if published is not None
            else "Your storefront uses the AfriCinemas default theme."
    );
    preset_list: list[dict[str, any]] = info["presets"];  # jac:ignore[W1037]

    presets = <section
        aria-labelledby="presets-heading"
        className="flex flex-col gap-3"
    >
        <h3 id="presets-heading" className="font-semibold">Start from a preset</h3>
        <div
            role="radiogroup"
            aria-labelledby="presets-heading"
            className="grid gap-3 sm:grid-cols-2"
        >
            {[
                <PresetCard
                    key={p["name"]}
                    preset={p}
                    checked={same_theme(p, current)}
                    on_choose={choose_preset}
                /> for p in preset_list
            ]}
        </div>
    </section>;

    mode_switch = <div role="group" aria-label="Colour mode" className="flex gap-2">
        {[
            <Button
                key={m}
                variant={"default" if m == mode else "outline"}
                aria-pressed={"true" if m == mode else "false"}
                className="min-h-11 px-5"
                onClick={lambda { set_mode(m); }}
            >
                {"Light" if m == "light" else "Dark"}
            </Button> for m in MODES
        ]}
    </div>;

    def fields(roles: list[str]) -> JsxElement {
        return
            <div className="grid gap-4 sm:grid-cols-2">
                {[
                    <ColourField
                        key={field_id(mode, r)}
                        mode={mode}
                        role={r}
                        value={current[mode][r]}
                        text={field_texts[field_id(mode, r)] or ""}
                        error={field_errors[field_id(mode, r)] or ""}
                        on_pick={pick}
                        on_type={type_hex}
                        on_leave={leave_hex}
                    /> for r in roles
                ]}
            </div>;
    }

    colours = <section
        aria-labelledby="colours-heading"
        className="flex flex-col gap-4"
    >
        <div className="flex flex-wrap items-center justify-between gap-3">
            <h3 id="colours-heading" className="font-semibold">Colours</h3>
            {mode_switch}
        </div>
        <p className="text-sm text-muted-foreground">
            Your storefront follows each visitor's device: light or dark. Set both.
        </p>
        {fields(key_roles())}
        <details className="rounded-lg border p-3">
            <summary className="flex min-h-11 cursor-pointer items-center font-medium">
                More colours
            </summary>
            <div className="pt-3">{fields(other_roles(options["roles"]))}</div>
        </details>
    </section>;

    type_and_shape = <section
        aria-labelledby="type-heading"
        className="grid gap-4 sm:grid-cols-2"
    >
        <h3 id="type-heading" className="font-semibold sm:col-span-2">
            Name, fonts and corners
        </h3>
        <div className="flex flex-col gap-1.5 sm:col-span-2">
            <Label htmlFor="theme-name">Theme name</Label>
            <Input
                id="theme-name"
                value={current["name"]}
                maxLength={40}
                onChange={lambda (e: any) { change_field("name", e.target.value); }}  # jac:ignore[W1037]
                className="min-h-11"
            />
        </div>
        <div className="flex flex-col gap-1.5">
            <Label htmlFor="display-font">Headings font</Label>
            <select
                id="display-font"
                value={current["display_font"]}
                onChange={lambda (e: any) { change_field(  # jac:ignore[W1037]
                    "display_font", e.target.value
                ); }}  # jac:ignore[W1037]
                className={SELECT_CLASSES}
            >
                {[
                    <option key={f} value={f}>{f}</option>
                    for f in options["display_fonts"]
                ]}
            </select>
        </div>
        <div className="flex flex-col gap-1.5">
            <Label htmlFor="body-font">Body font</Label>
            <select
                id="body-font"
                value={current["body_font"]}
                onChange={lambda (e: any) { change_field(  # jac:ignore[W1037]
                    "body_font", e.target.value
                ); }}  # jac:ignore[W1037]
                className={SELECT_CLASSES}
            >
                {[
                    <option key={f} value={f}>{f}</option>
                    for f in options["body_fonts"]
                ]}
            </select>
        </div>
        <div className="flex flex-col gap-1.5">
            <Label htmlFor="radius">Corners</Label>
            <select
                id="radius"
                value={current["radius"]}
                onChange={lambda (e: any) { change_field("radius", e.target.value); }}  # jac:ignore[W1037]
                className={SELECT_CLASSES}
            >
                {[
                    <option key={r} value={r}>{radius_label(r)}</option>
                    for r in options["radii"]
                ]}
            </select>
        </div>
    </section>;

    logo_section = <section
        aria-labelledby="logo-heading"
        className="flex flex-col gap-3"
    >
        <h3 id="logo-heading" className="font-semibold">Logo</h3>
        {logo
            and <div className="flex flex-wrap items-center gap-3">
                <img
                    src={logo}
                    alt="Your logo"
                    data-testid="logo-preview"
                    className="h-12 w-auto max-w-full rounded border bg-muted p-1"
                />
                <Button
                    variant="outline"
                    className="min-h-11 px-5"
                    disabled={busy != ""}
                    onClick={drop_logo}
                >
                    Remove logo
                </Button>
            </div>}
        <div className="flex flex-col gap-1.5">
            <Label htmlFor="logo-file">
                {"Replace logo" if logo else "Upload a logo"}
            </Label>
            <input
                id="logo-file"
                type="file"
                accept={LOGO_TYPES}
                disabled={busy != ""}
                onChange={choose_logo}
                className="min-h-11 text-sm file:mr-3 file:min-h-11 file:rounded-md file:border file:bg-card file:px-4 file:font-medium"
            />
            <p className="text-sm text-muted-foreground">
                PNG, JPEG or WebP, at least 64 × 64 pixels, up to 5 MB. A transparent background works best.
            </p>
        </div>
    </section>;

    history = <section
        aria-labelledby="history-heading"
        className="flex flex-col gap-3"
    >
        <h3 id="history-heading" className="font-semibold">Published versions</h3>
        {len(versions) == 0
            and <p className="text-sm text-muted-foreground">Nothing published yet.</p>}
        <ul className="flex flex-col gap-2" data-testid="version-history">
            {[
                <li
                    key={v["version"]}
                    className="flex flex-wrap items-center justify-between gap-3 rounded-lg border bg-card px-4 py-2"
                >
                    <span className="flex flex-col">
                        <span className="font-medium">{version_label(v)}</span>
                        <span className="text-sm text-muted-foreground">
                            {"Live now" if i == 0 else published_on(v["published_at"])}
                        </span>
                    </span>
                    {i > 0
                        and <Button
                            variant="outline"
                            className="min-h-11 px-4"
                            disabled={busy != ""}
                            onClick={lambda { set_restoring(v["version"]); }}
                        >
                            Restore version {v["version"]}
                        </Button>}
                </li> for (i, v) in enumerate(versions)
            ]}
        </ul>
        {restoring > 0
            and <div
                className="flex flex-col gap-3 rounded-lg border p-4"
                data-testid="restore-confirm"
                role="group"
                aria-labelledby="restore-confirm-title"
            >
                <p id="restore-confirm-title" className="font-medium">
                    Restore version {restoring}?
                </p>
                <p className="text-sm text-muted-foreground">
                    Your storefront will show version {restoring} again, published as a new version. It also replaces your current draft.
                </p>
                <div className="flex flex-wrap gap-3">
                    <Button
                        className="min-h-11 px-5"
                        onClick={lambda { restore(restoring); }}
                    >
                        Restore version {restoring}
                    </Button>
                    <Button
                        variant="ghost"
                        className="min-h-11 px-5"
                        onClick={lambda { set_restoring(0); }}
                    >
                        Cancel
                    </Button>
                </div>
            </div>}
    </section>;

    actions = <div className="flex flex-col gap-3">
        <div className="flex flex-wrap items-center gap-3">
            <Button
                variant="outline"
                className="min-h-11 px-5"
                disabled={busy != "" or not unsaved or invalid}
                onClick={save_draft}
            >
                {busy == "saving" and <Spinner aria-hidden="true"/>}{"Saving…"
                    if busy == "saving"
                    else "Save draft"}
            </Button>
            <Button
                className="min-h-11 px-5"
                disabled={busy != "" or invalid}
                onClick={publish}
            >
                {busy == "publishing" and <Spinner aria-hidden="true"/>}{"Publishing…"
                    if busy == "publishing"
                    else "Publish"}
            </Button>
            {unsaved
                and <span className="text-sm text-muted-foreground">
                    Unsaved changes
                </span>}
        </div>
        <p
            role="status"
            aria-live="polite"
            className="text-sm"
            data-testid="branding-message"
        >
            {message}
        </p>
        {len(adjusted) > 0
            and <Alert data-testid="adjusted-colours">
                <AlertTitle>We adjusted some colours so text stays readable</AlertTitle>
                <AlertDescription>
                    <ul className="list-disc pl-4">
                        {[
                            <li key={i}>{adjusted_text(a)}</li>
                            for (i, a) in enumerate(adjusted)
                        ]}
                    </ul>
                </AlertDescription>
            </Alert>}
    </div>;

    return
        <div className="flex flex-col gap-6" data-testid="branding">
            <div className="flex flex-col gap-2">
                <h2 className="text-xl font-semibold">Branding</h2>
                <div className="flex flex-wrap items-center gap-3">
                    <Badge
                        variant={"default" if published is not None else "secondary"}
                        data-testid="branding-status"
                    >
                        {status}
                    </Badge>
                    <a
                        href={"/c/" + slug}
                        className="inline-flex min-h-11 items-center text-sm font-medium underline underline-offset-4"
                    >
                        View your storefront
                    </a>
                </div>
            </div>
            <div className="grid gap-8 lg:grid-cols-[minmax(0,1fr)_20rem]">
                <div className="lg:order-2">
                    <div className="flex flex-col gap-2 lg:sticky lg:top-8">
                        <h3 className="font-semibold">Preview</h3>
                        <ThemePreview
                            theme={current}
                            mode={mode}
                            options={options}
                            logo={logo}
                            cinema={cinema}
                        />
                    </div>
                </div>
                <div className="flex min-w-0 flex-col gap-8 lg:order-1">
                    {presets}{colours}{type_and_shape}{logo_section}{actions}{history}
                </div>
            </div>
        </div>;
}
