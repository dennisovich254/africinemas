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
    get_branding,  # jac:ignore[W2037] authenticated endpoint
    save_theme,  # jac:ignore[W2037]
    upload_logo,  # jac:ignore[W2037]
    suggest_themes,  # jac:ignore[W2037]
    draw_pattern,  # jac:ignore[W2037]
    remove_pattern,  # jac:ignore[W2037]
    set_pattern_places,  # jac:ignore[W2037]
    remove_logo,  # jac:ignore[W2037]
    publish_theme,  # jac:ignore[W2037]
    rollback_theme  # jac:ignore[W2037]
}
import from .branding_model {
    role_label,
    radius_label,
    scheme_of,
    scheme_label,
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
import from .form_parts { read_as_base64 }

glob MODES: list[str] = ["light", "dark"],
     IDEAS_KEPT: int = 6,
     # Where the storefront can show the pattern (ADR-0045), as the owner reads them.
     PLACE_LABELS: list[tuple[str, str]] = [
         ("hero", "Behind the hero"),
         ("header", "Header"),
         ("sections", "Behind home page sections"),
         ("footer", "Footer"),
         ("tickets", "Ticket pages")
     ],
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

# One theme the AI designed from the logo (ADR-0043): its mood, why, and its colours.
def IdeaCard(
    idea: dict[str, any],  # jac:ignore[W1037]
    on_use: any  # jac:ignore[W1037]
) -> JsxElement {
    theme: dict[str, any] = idea["theme"];  # jac:ignore[W1037]
    swatches = ["background", "surface", "accent", "ink"];
    return
        <div
            className="flex h-full flex-col gap-3 rounded-lg border bg-card p-3"
            data-testid="theme-idea"
        >
            <span className="font-medium">{theme["name"]}</span>
            <span className="flex gap-1" aria-hidden="true">
                {[
                    <span
                        key={f"{mode}-{role}"}
                        className="size-5 rounded border"
                        style={{"background": theme[mode][role]}}
                    ></span> for mode in MODES for role in swatches
                ]}
            </span>
            {idea["reason"]
                and <p className="text-sm text-muted-foreground">{idea["reason"]}</p>}
            <Button
                variant="outline"
                className="mt-auto min-h-11 self-start px-4"
                onClick={lambda { on_use(idea); }}
            >
                Try this theme
            </Button>
        </div>;
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
    [ideas, set_ideas] = useState([]);
    [pattern, set_pattern] = useState("");
    [places, set_places] = useState([]);
    [pattern_note, set_pattern_note] = useState("");
    [ideas_note, set_ideas_note] = useState("");

    def show(answer: dict[str, any]) {  # jac:ignore[W1037]
        draft: dict[str, any] = answer["branding"]["draft"];  # jac:ignore[W1037]
        set_data(answer);
        set_theme(draft["theme"]);
        set_saved(draft["theme"]);
        set_texts(texts_for(draft["theme"]));
        set_errors({});
        set_logo(draft["logo"]);
        set_pattern(draft["pattern"]);
        set_places(draft["pattern_places"]);
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

    async def ask_ideas {
        answer: any = None;  # jac:ignore[W1037]
        set_busy("suggesting");
        set_ideas_note("");
        try {
            answer = await suggest_themes(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("suggest_themes failed", e);
            set_busy("");
            set_ideas_note(
                "We couldn't get ideas. Check your connection and try again."
            );
            return;
        }
        set_busy("");
        if not answer["ok"] {
            set_ideas_note(answer["error"]["message"]);
            return;
        }
        # One idea per ask (Groq's per-minute limit): newest first, earlier ones kept.
        fresh: list[dict[str, any]] = answer["proposals"];  # jac:ignore[W1037]
        names = [i["theme"]["name"] for i in fresh];
        earlier: list[dict[str, any]] = ideas;  # jac:ignore[W1037]
        kept: list[dict[str, any]] = [  # jac:ignore[W1037]
            i
            for i in earlier
            if i["theme"]["name"] not in names
        ];
        set_ideas((fresh + kept)[:IDEAS_KEPT]);
        left: int = answer["remaining"];
        said = "Here's a theme made from your logo. Try it in the preview, or ask for another."
            if answer["from_ai"]
            else "The AI couldn't answer just now, so here's a theme made from your logo's main colour.";
        more = " That was your last set of ideas for today."
            if left == 0
            else f" You can ask {left} more times today.";
        set_ideas_note(said + more);
    }

    async def draw {
        answer: any = None;  # jac:ignore[W1037]
        set_busy("drawing");
        set_pattern_note("");
        try {
            answer = await draw_pattern(slug, current);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("draw_pattern failed", e);
            set_busy("");
            set_pattern_note(
                "We couldn't draw a pattern. Check your connection and try again."
            );
            return;
        }
        set_busy("");
        if not answer["ok"] {
            set_pattern_note(answer["error"]["message"]);
            return;
        }
        set_pattern(answer["pattern"]);
        set_places(answer["places"]);
        left: int = answer["remaining"];
        set_pattern_note(
            "Here's your pattern. Choose where it shows, then publish to put it on your storefront."
                + (
                    " That was your last drawing for today."
                        if left == 0
                        else f" You can draw {left} more today."
                )
        );
    }

    async def drop_pattern {
        answer: any = None;  # jac:ignore[W1037]
        set_busy("drawing");
        try {
            answer = await remove_pattern(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("remove_pattern failed", e);
        }
        set_busy("");
        if answer and answer["ok"] {
            set_pattern("");
            set_pattern_note(
                "Pattern removed. Publish to take it off your storefront."
            );
        }
    }

    async def toggle_place(place: str) {
        chosen: list[str] = places;
        wanted = [
            p
            for p in chosen
            if p != place
        ]
            if place in chosen
            else chosen + [place];
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await set_pattern_places(slug, wanted);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("set_pattern_places failed", e);
            set_pattern_note(
                "We couldn't save that. Check your connection and try again."
            );
            return;
        }
        if answer["ok"] {
            set_places(answer["places"]);
            set_pattern_note("Saved. Publish to show it on your storefront.");
        }
    }

    def use_idea(idea: dict[str, any]) {  # jac:ignore[W1037]
        choose_preset(idea["theme"]);
        set_message(
            f"{idea['theme'][
                'name'
            ]} is in the editor. Adjust it, then save or publish to keep it."
        );
    }

    def change_scheme(value: str) {
        # The preview shows the mode the storefront will now always wear.
        change_field("scheme", value);
        if value != "auto" {
            set_mode(value);
        }
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
        <div className="flex flex-col gap-1.5">
            <Label htmlFor="scheme">Light or dark</Label>
            <select
                id="scheme"
                value={scheme_of(current)}
                onChange={lambda (e: any) { change_scheme(e.target.value); }}  # jac:ignore[W1037]
                className={SELECT_CLASSES}
            >
                {[
                    <option key={m} value={m}>{scheme_label(m)}</option>
                    for m in options["schemes"]
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

    idea_list: list[dict[str, any]] = ideas;  # jac:ignore[W1037]
    ideas_section = <section
        aria-labelledby="ideas-heading"
        className="flex flex-col gap-3"
        data-testid="theme-ideas"
    >
        <h3 id="ideas-heading" className="font-semibold">Ideas from your logo</h3>
        <p className="text-sm text-muted-foreground">
            {"AI looks at your logo and suggests a theme made from its colours; ask again for another. Try one in the preview, then adjust it."
                if logo
                else "Upload your logo above, and AI will suggest themes made from its colours."}
        </p>
        {logo
            and <Button
                variant="outline"
                className="min-h-11 self-start px-5"
                disabled={busy != ""}
                onClick={ask_ideas}
            >
                {busy == "suggesting" and <Spinner aria-hidden="true"/>}{"Looking at your logo…"
                    if busy == "suggesting"
                    else ("Suggest another" if len(ideas) > 0 else "Suggest a theme")}
            </Button>}
        {ideas_note
            and <p
                role="status"
                className="text-sm text-muted-foreground"
                data-testid="ideas-note"
            >
                {ideas_note}
            </p>}
        {len(idea_list) > 0
            and <ul className="grid gap-3 sm:grid-cols-2">
                {[
                    <li key={i["theme"]["name"]}>
                        <IdeaCard idea={i} on_use={use_idea}/>
                    </li> for i in idea_list
                ]}
            </ul>}
    </section>;

    shown_places: list[str] = places;
    pattern_section = <section
        aria-labelledby="pattern-heading"
        className="flex flex-col gap-3"
        data-testid="theme-pattern"
    >
        <h3 id="pattern-heading" className="font-semibold">Pattern from your logo</h3>
        <p className="text-sm text-muted-foreground">
            {"AI draws a light pattern from the flowers, birds or shapes in your logo, in your theme's colours. It shows faintly behind the parts of your storefront you choose."
                if logo
                else "Upload your logo above, and AI can draw a pattern from it."}
        </p>
        {pattern
            and <img
                src={pattern}
                alt="The pattern drawn from your logo"
                className="max-h-48 w-full rounded-lg border object-cover"
                data-testid="pattern-preview"
            />}
        {logo
            and <div className="flex flex-wrap gap-3">
                <Button
                    variant="outline"
                    className="min-h-11 px-5"
                    disabled={busy != ""}
                    onClick={draw}
                >
                    {busy == "drawing" and <Spinner aria-hidden="true"/>}{"Drawing… about 15 seconds"
                        if busy == "drawing"
                        else ("Draw again" if pattern else "Draw a pattern")}
                </Button>
                {pattern
                    and <Button
                        variant="ghost"
                        className="min-h-11 px-4"
                        disabled={busy != ""}
                        onClick={drop_pattern}
                    >
                        Remove pattern
                    </Button>}
            </div>}
        {pattern
            and <fieldset className="flex flex-col gap-2" data-testid="pattern-places">
                <legend className="mb-1 text-sm font-medium">Show it</legend>
                {[
                    <label
                        key={key}
                        className="flex min-h-11 cursor-pointer items-center gap-3 text-sm"
                    >
                        <input
                            type="checkbox"
                            checked={key in shown_places}
                            onChange={lambda { toggle_place(key); }}
                            className="size-5"
                        />
                        {label}
                    </label> for (key, label) in PLACE_LABELS
                ]}
            </fieldset>}
        {pattern_note
            and <p
                role="status"
                className="text-sm text-muted-foreground"
                data-testid="pattern-note"
            >
                {pattern_note}
            </p>}
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
                    {presets}{colours}{type_and_shape}{logo_section}{ideas_section}{pattern_section}{actions}{history}
                </div>
            </div>
        </div>;
}
