"""`/app/:slug/settings/home-page`: the cinema's home page editor (P4.1b), on the
core/homepage endpoints.

Owners pick a template, then show, hide, reorder and fill in sections, watching a live
preview of their storefront (the real storefront sections, in the cinema's published
theme, filled from today's programme by preview_home_page). The preview also checks the
draft as it changes, so problems show under their fields before saving. "Save draft"
keeps the changes private; "Publish" saves and puts them on the storefront. Each
publish is a version; restoring an earlier one asks first, then publishes it again.
"""

import from react { useState, useEffect }
import from ...components.ui.badge { Badge }
import from ...components.ui.button { Button }
import from ...components.ui.spinner { Spinner }
import from core.homepage.home_api {
    get_home_page,  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)
    save_home_page,  # jac:ignore[W2037]
    publish_home_page,  # jac:ignore[W2037]
    rollback_home_page,  # jac:ignore[W2037]
    preview_home_page,  # jac:ignore[W2037]
    upload_home_photo,  # jac:ignore[W2037]
    get_home_photo,  # jac:ignore[W2037]
    remove_home_photo  # jac:ignore[W2037]
}
import from core.theming.branding_api { public_branding }
import from ..storefront.HomeSections { HomeBlock, home_blocks, FeaturedHero }
import from .home_page_model {
    SECTION_LABELS,
    TEMPLATE_INFO,
    same_page,
    with_template,
    moved,
    with_visible,
    with_field,
    problems_by_path,
    version_text
}
import from .HomePageFields { SectionFields, PhotoChoices }
import from .form_parts { read_as_base64 }

glob PREVIEW_DELAY_MS: int = 500;

def published_on(stamp: str) -> str {
    moment: any = new(Date, stamp);  # jac:ignore[W1037,W2001]
    return moment.toLocaleString();
}

def TemplateCard(
    info: dict[str, str],
    checked: bool,
    on_choose: any  # jac:ignore[W1037]
) -> JsxElement {
    return
        <label
            className="flex min-h-11 cursor-pointer flex-col gap-1 rounded-lg border bg-card p-3 has-[:checked]:border-primary has-[:checked]:bg-muted has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-ring"
        >
            <input
                type="radio"
                name="template"
                value={info["name"]}
                checked={checked}
                onChange={lambda { on_choose(info["name"]); }}
                className="sr-only"
            />
            <span className="font-medium">{info["label"]}</span>
            <span className="text-sm text-muted-foreground">{info["text"]}</span>
        </label>;
}

def:pub HomePageSection(slug: str) -> JsxElement {
    [data, set_data] = useState(None);
    [page, set_page] = useState(None);
    [saved, set_saved] = useState(None);
    [problems, set_problems] = useState([]);
    [preview, set_preview] = useState(None);
    [tz, set_tz] = useState("Africa/Nairobi");
    [device, set_device] = useState("phone");
    [view, set_view] = useState("edit");
    [photos, set_photos] = useState([]);
    [thumbs, set_thumbs] = useState({});
    [theme_css, set_theme_css] = useState("");
    [busy, set_busy] = useState("");
    [message, set_message] = useState("");
    [restoring, set_restoring] = useState(0);
    [failed, set_failed] = useState(False);

    async def load {
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await get_home_page(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("get_home_page failed", e);
            set_failed(True);
            return;
        }
        if not answer["ok"] {
            set_failed(True);
            return;
        }
        set_data(answer);
        set_page(answer["home"]["draft"]);
        set_saved(answer["home"]["draft"]);
        set_photos(answer["home"]["photos"]);
    }

    def start_loading {
        load();
    }
    useEffect(start_loading, [slug]);

    async def load_theme {
        shown: any = None;  # jac:ignore[W1037]
        try {
            shown = await public_branding(slug);
        } except Exception as e {
            console.warn("public_branding failed", e);
            return;
        }
        if shown["ok"] {
            set_theme_css(shown["branding"]["css"]);
        }
    }

    def start_theme {
        load_theme();
    }
    useEffect(start_theme, [slug]);

    def wear_theme -> any {  # jac:ignore[W1037]
        # The cinema's published theme, for the preview only: its CSS applies inside
        # [data-surface="storefront"], which only the preview carries here.
        doc: any = document;  # jac:ignore[W1037,W2001]
        tag: any = doc.createElement("style");  # jac:ignore[W1037]
        tag.textContent = theme_css;
        doc.head.appendChild(tag);
        return lambda { doc.head.removeChild(tag); };
    }
    useEffect(wear_theme, [theme_css]);

    async def load_thumbs {
        have: list[str] = photos;
        known: dict[str, str] = thumbs;
        missing = [
            p
            for p in have
            if p not in known
        ];
        if len(missing) == 0 {
            return;
        }
        found: dict[str, str] = {};
        for p in missing {
            try {
                shown: any = await get_home_photo(slug, p);  # jac:ignore[W1037,W2037]
                if shown["ok"] {
                    found[p] = shown["photo"];
                }
            } except Exception as e {
                console.warn("get_home_photo failed", e);
            }
        }
        merged: dict[str, str] = {};
        for key in known {
            merged[key] = known[key];
        }
        for key in found {
            merged[key] = found[key];
        }
        set_thumbs(merged);
    }

    def start_thumbs {
        load_thumbs();
    }
    useEffect(start_thumbs, [photos]);

    async def refresh_preview(draft: dict[str, any]) {  # jac:ignore[W1037]
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await preview_home_page(slug, draft);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("preview_home_page failed", e);
            return;
        }
        if answer["ok"] {
            set_preview(answer["page"]);
            set_tz(answer["cinema"]["timezone"]);
            set_problems([]);
        } elif answer["error"]["code"] == "invalid_page" {
            set_problems(answer["error"]["problems"]);
        }
    }

    def schedule_preview -> any {  # jac:ignore[W1037]
        # Redraws the preview (and checks the draft) once typing pauses.
        # An effect must return a cleanup function or nothing: Jac's None would reach
        # React as null and break it ("destroy is not a function").
        win: any = window;  # jac:ignore[W1037,W2001]
        if page is None {
            return lambda {};
        }
        draft: dict[str, any] = page;  # jac:ignore[W1037]
        timer: any = win.setTimeout(  # jac:ignore[W1037,W6001] client-only debounce
            lambda { refresh_preview(draft); }, PREVIEW_DELAY_MS
        );
        return lambda { win.clearTimeout(timer); };  # jac:ignore[W6001]
    }
    useEffect(schedule_preview, [page]);

    if failed {
        return
            <p role="alert" className="text-destructive">
                We couldn't load your home page. Reload to try again.
            </p>;
    }
    if data is None or page is None {
        return
            <p role="status" className="flex items-center gap-2 text-muted-foreground">
                <Spinner aria-hidden="true"/>
                Loading your home page…
            </p>;
    }
    info: dict[str, any] = data;  # jac:ignore[W1037]
    current: dict[str, any] = page;  # jac:ignore[W1037]
    options: dict[str, any] = info["options"];  # jac:ignore[W1037]
    home: dict[str, any] = info["home"];  # jac:ignore[W1037]
    published: dict[str, any] | None = home["published"];  # jac:ignore[W1037]
    versions: list[dict[str, any]] = home["versions"];  # jac:ignore[W1037]
    errors = problems_by_path(problems);
    unsaved = not same_page(current, saved);
    invalid = len(problems) > 0;
    sections: list[dict[str, any]] = current["sections"];  # jac:ignore[W1037]

    def edit(changed: dict[str, any]) {  # jac:ignore[W1037]
        set_page(changed);
        set_message("");
    }

    async def save -> bool {
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await save_home_page(slug, current);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("save_home_page failed", e);
            set_message("We couldn't save your page. Try again.");
            return False;
        }
        if not answer["ok"] {
            if answer["error"]["code"] == "invalid_page" {
                set_problems(answer["error"]["problems"]);
            }
            set_message(answer["error"]["message"]);
            return False;
        }
        set_page(answer["page"]);
        set_saved(answer["page"]);
        return True;
    }

    async def save_draft {
        set_busy("saving");
        if await save() {
            set_message("Draft saved. Publish to show it on your storefront.");
        }
        set_busy("");
    }

    async def reload_versions {
        refreshed: any = await get_home_page(slug);  # jac:ignore[W1037,W2037]
        if refreshed["ok"] {
            set_data(refreshed);
        }
    }

    async def publish {
        set_busy("publishing");
        if unsaved and not await save() {
            set_busy("");
            return;
        }
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await publish_home_page(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("publish_home_page failed", e);
            set_busy("");
            set_message("We couldn't publish your page. Try again.");
            return;
        }
        set_busy("");
        if not answer["ok"] {
            set_message(answer["error"]["message"]);
            return;
        }
        await reload_versions();
        set_message(f"Version {answer['version']} is live on your storefront.");
    }

    async def restore(version: int) {
        set_busy("restoring");
        set_restoring(0);
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await rollback_home_page(slug, version);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("rollback_home_page failed", e);
            set_busy("");
            set_message("We couldn't restore that version. Try again.");
            return;
        }
        set_busy("");
        if not answer["ok"] {
            set_message(answer["error"]["message"]);
            return;
        }
        refreshed: any = await get_home_page(slug);  # jac:ignore[W1037,W2037]
        if refreshed["ok"] {
            set_data(refreshed);
            set_page(refreshed["home"]["draft"]);
            set_saved(refreshed["home"]["draft"]);
        }
        set_message(
            f"Version {version} is live again, as version {answer['version']}."
        );
    }

    async def upload_photo(e: any) {  # jac:ignore[W1037]
        file: any = e.target.files[0];  # jac:ignore[W1037]
        if not file {
            return;
        }
        set_busy("photo");
        set_message("");
        answer: any = None;  # jac:ignore[W1037]
        try {
            encoded = await read_as_base64(file);
            answer = await upload_home_photo(slug, file.type, encoded);  # jac:ignore[W2037]
        } except Exception as err {
            console.warn("upload_home_photo failed", err);
            set_busy("");
            set_message("We couldn't upload that photo. Try again.");
            return;
        }
        e.target.value = "";
        set_busy("");
        if not answer["ok"] {
            set_message(answer["error"]["message"]);
            return;
        }
        have: list[str] = photos;
        set_photos(have + [answer["photo"]]);
        set_message("Photo uploaded. Tick it to show it on your page.");
    }

    async def remove_photo(photo: str) {
        set_busy("photo");
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await remove_home_photo(slug, photo);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("remove_home_photo failed", e);
            set_busy("");
            set_message("We couldn't delete that photo. Try again.");
            return;
        }
        set_busy("");
        if not answer["ok"] {
            set_message(answer["error"]["message"]);
            return;
        }
        set_photos(
            [
                p
                for p in photos
                if p != photo
            ]
        );
        # The server took it out of the saved draft too.
        for (i, s) in enumerate(sections) {
            if s["type"] == "about" {
                left = [
                    p
                    for p in s["fields"]["photos"]
                    if p != photo
                ];
                set_page(with_field(current, i, "photos", left));
                set_saved(with_field(saved, i, "photos", left));
            }
        }
        set_message("Photo deleted.");
    }

    status = (
        f"Version {published['version']} is live"
            if published is not None
            else "Your storefront shows the default page."
    );

    templates = <section
        aria-labelledby="template-heading"
        className="flex flex-col gap-3"
    >
        <h3 id="template-heading" className="font-semibold">Template</h3>
        <div
            role="radiogroup"
            aria-labelledby="template-heading"
            className="grid gap-3 sm:grid-cols-3"
        >
            {[
                <TemplateCard
                    key={t["name"]}
                    info={t}
                    checked={current["template"] == t["name"]}
                    on_choose={lambda (name: str) { edit(
                        with_template(current, name)
                    ); }}
                /> for t in TEMPLATE_INFO
            ]}
        </div>
        {errors["template"]
            and <p role="alert" className="text-sm text-destructive">
                {errors["template"]}
            </p>}
    </section>;

    section_list = <section
        aria-labelledby="sections-heading"
        className="flex flex-col gap-3"
    >
        <h3 id="sections-heading" className="font-semibold">Sections</h3>
        <p className="text-sm text-muted-foreground">
            Sections with nothing to show (no showtimes today, empty text) stay off your page.
        </p>
        <ol className="flex flex-col gap-3">
            {[
                <li
                    key={s["type"]}
                    data-testid={f"edit-{s['type']}"}
                    className="flex flex-col gap-3 rounded-lg border bg-card p-4"
                >
                    <div className="flex flex-wrap items-center justify-between gap-3">
                        <span className="font-medium">{SECTION_LABELS[s["type"]]}</span>
                        <div className="flex flex-wrap items-center gap-2">
                            <label
                                className="flex min-h-11 cursor-pointer items-center gap-2 px-2 text-sm"
                            >
                                <input
                                    type="checkbox"
                                    className="size-5"
                                    checked={s["visible"]}
                                    onChange={lambda { edit(
                                        with_visible(current, i, not s["visible"])
                                    ); }}
                                />
                                Show
                            </label>
                            <Button
                                variant="outline"
                                className="min-h-11 px-3"
                                disabled={i == 0}
                                aria-label={f"Move {SECTION_LABELS[s['type']]} up"}
                                onClick={lambda { edit(moved(current, i, -1)); }}
                            >
                                Up
                            </Button>
                            <Button
                                variant="outline"
                                className="min-h-11 px-3"
                                disabled={i == len(sections) - 1}
                                aria-label={f"Move {SECTION_LABELS[s['type']]} down"}
                                onClick={lambda { edit(moved(current, i, 1)); }}
                            >
                                Down
                            </Button>
                        </div>
                    </div>
                    <details className="rounded-md border px-3">
                        <summary
                            className="flex min-h-11 cursor-pointer items-center text-sm font-medium"
                        >
                            Edit content
                        </summary>
                        <div className="pb-4 pt-2">
                            <SectionFields
                                page={current}
                                index={i}
                                options={options}
                                errors={errors}
                                on_page={edit}
                                photo_editor={s["type"] == "about"
                                    and <PhotoChoices
                                        page={current}
                                        index={i}
                                        photos={photos}
                                        thumbs={thumbs}
                                        limit={options["limits"]["photos"]}
                                        errors={errors}
                                        busy={busy != ""}
                                        on_page={edit}
                                        on_upload={upload_photo}
                                        on_remove={remove_photo}
                                    />}
                            />
                        </div>
                    </details>
                </li> for (i, s) in enumerate(sections)
            ]}
        </ol>
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
            {invalid
                and <span className="text-sm text-destructive">
                    Fix the problems marked below first.
                </span>}
        </div>
        <p
            role="status"
            aria-live="polite"
            className="text-sm"
            data-testid="home-message"
        >
            {message}
        </p>
    </div>;

    history = <section
        aria-labelledby="home-history-heading"
        className="flex flex-col gap-3"
    >
        <h3 id="home-history-heading" className="font-semibold">Published versions</h3>
        {len(versions) == 0
            and <p className="text-sm text-muted-foreground">Nothing published yet.</p>}
        <ul className="flex flex-col gap-2" data-testid="home-versions">
            {[
                <li
                    key={v["version"]}
                    className="flex flex-wrap items-center justify-between gap-3 rounded-lg border bg-card px-4 py-2"
                >
                    <span className="flex flex-col">
                        <span className="font-medium">{version_text(v)}</span>
                        <span className="text-sm text-muted-foreground">
                            {"Live now" if n == 0 else published_on(v["published_at"])}
                        </span>
                    </span>
                    {n > 0
                        and <Button
                            variant="outline"
                            className="min-h-11 px-4"
                            disabled={busy != ""}
                            onClick={lambda { set_restoring(v["version"]); }}
                        >
                            Restore version {v["version"]}
                        </Button>}
                </li> for (n, v) in enumerate(versions)
            ]}
        </ul>
        {restoring > 0
            and <div
                className="flex flex-col gap-3 rounded-lg border p-4"
                data-testid="home-restore-confirm"
                role="group"
                aria-labelledby="home-restore-title"
            >
                <p id="home-restore-title" className="font-medium">
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

    shown: dict[str, any] | None = preview;  # jac:ignore[W1037]
    shown_template: str = shown["template"] if shown is not None else "";
    preview_box = <div className="flex flex-col gap-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
            <p className="text-sm text-muted-foreground">
                Your draft, filled with today's programme, in your published theme.
            </p>
            <div role="group" aria-label="Preview size" className="flex gap-2">
                {[
                    <Button
                        key={d}
                        variant={"default" if d == device else "outline"}
                        aria-pressed={"true" if d == device else "false"}
                        className="min-h-11 px-4"
                        onClick={lambda { set_device(d); }}
                    >
                        {"Phone" if d == "phone" else "Desktop"}
                    </Button> for d in ["phone", "desktop"]
                ]}
            </div>
        </div>
        {invalid
            and <p role="alert" className="text-sm text-destructive">
                Your draft has problems to fix on the Edit tab, so this shows the last version without them.
            </p>}
        <div
            data-surface="storefront"
            data-testid="home-preview"
            data-template={shown_template}
            data-device={device}
            className={"mx-auto w-full overflow-hidden rounded-xl border bg-background p-4 text-foreground "
                + ("max-w-[375px]" if device == "phone" else "max-w-5xl")}
        >
            {shown is None
                and <p role="status" className="text-sm text-muted-foreground">
                    Drawing the preview…
                </p>}{shown is not None
                and len(shown["sections"]) == 0
                and <p className="text-sm text-muted-foreground">
                    Nothing to show yet: add showtimes or fill in a section.
                </p>}{shown is not None
                and <div
                    className={"@container flex flex-col gap-12 "
                        + (
                            "mx-auto w-full max-w-2xl"
                                if shown_template == "compact"
                                else ""
                        )}
                >
                    {[
                        (
                            <FeaturedHero
                                key={f"{n}"}
                                slug={slug}
                                section={b[0]}
                                under_header={False}
                            />
                        )
                            if shown_template == "marquee"
                                and n == 0
                                and b[0]["type"] == "hero"
                            else <HomeBlock
                                key={f"{n}"}
                                slug={slug}
                                block={b}
                                tz={tz}
                                template={shown_template}
                            /> for (n, b) in enumerate(home_blocks(shown["sections"]))
                    ]}
                </div>}
        </div>
    </div>;

    tabs = [("edit", "Edit"), ("preview", "Preview")];
    return
        <div className="flex flex-col gap-6" data-testid="home-editor">
            <div className="flex flex-wrap items-center gap-3">
                <Badge
                    variant={"default" if published is not None else "secondary"}
                    data-testid="home-status"
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
            {actions}
            <div role="tablist" aria-label="Home page" className="flex gap-2 border-b">
                {[
                    <button
                        key={key}
                        type="button"
                        role="tab"
                        id={f"home-tab-{key}"}
                        data-testid={f"home-tab-{key}"}
                        aria-selected={"true" if view == key else "false"}
                        aria-controls={f"home-panel-{key}"}
                        onClick={lambda { set_view(key); }}
                        className={"-mb-px inline-flex min-h-11 items-center border-b-2 px-4 text-sm font-medium "
                            + (
                                "border-primary text-foreground"
                                    if view == key
                                    else "border-transparent text-muted-foreground hover:text-foreground"
                            )}
                    >
                        {label}
                    </button> for (key, label) in tabs
                ]}
            </div>
            <div
                role="tabpanel"
                id={f"home-panel-{view}"}
                aria-labelledby={f"home-tab-{view}"}
                className="min-w-0"
            >
                {view == "edit"
                    and <div className="flex max-w-3xl flex-col gap-8">
                        {templates}{section_list}{history}
                    </div>}{view == "preview" and preview_box}
            </div>
        </div>;
}
