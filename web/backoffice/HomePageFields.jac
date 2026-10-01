"""The fields of each home-page section, in the editor (P4.1b).

Every field has a visible label and shows its problem right under it, from the
server's field paths ("sections.2.fields.map_url"). Lists (opening hours, links,
questions) add and remove rows; movies and photos are chosen with checkboxes. Each
change hands a whole new page to `on_page`.
"""

import from ...components.ui.button { Button }
import from ...components.ui.label { Label }
import from .form_parts { TextField, FieldError }
import from .home_page_model {
    with_field,
    with_row_field,
    with_row_added,
    with_row_removed,
    toggled
}

glob SELECT_CLASSES: str = "min-h-11 w-full rounded-md border border-input bg-background px-3 text-sm",
     CHECK_ROW: str = "flex min-h-11 cursor-pointer items-center gap-3 rounded-md border px-3 has-[:checked]:border-primary has-[:checked]:bg-muted has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-ring",
     # Each list field's row fields: (key, label, multiline).
     ROW_FIELDS: dict[str, list[tuple[str, str, bool]]] = {
         "hours": [("days", "Days", False), ("times", "Times", False)],
         "links": [("label", "Name", False), ("url", "Web address", False)],
         "items": [("question", "Question", False), ("answer", "Answer", True)]
     },
     ROW_NAMES: dict[str, str] = {
         "hours": "opening hours",
         "links": "link",
         "items": "question"
     };

def _id(index: int, name: str) -> str {
    return f"home-{index}-{name}";
}

def RowList(  # jac:ignore[W3030] a list field: page, section, field, limit, errors and change handler
    page: dict[str, any],  # jac:ignore[W1037]
    index: int,
    name: str,
    legend: str,
    limit: int,
    errors: dict[str, str],
    on_page: any  # jac:ignore[W1037]
) -> JsxElement {
    rows: list[dict[str, str]] = page["sections"][index]["fields"][name];
    base = f"sections.{index}.fields.{name}";
    return
        <fieldset className="flex flex-col gap-3">
            <legend className="mb-1 text-sm font-medium">{legend}</legend>
            {[
                <div
                    key={f"{r}"}
                    data-testid={f"row-{name}"}
                    className="flex flex-col gap-3 rounded-lg border p-3"
                >
                    {[
                        <TextField
                            key={key}
                            field_id={f"{_id(index, name)}-{r}-{key}"}
                            label={label}
                            value={row[key]}
                            multiline={multiline}
                            error={errors[f"{base}.{r}.{key}"] or ""}
                            on_value={lambda (text: str) { on_page(
                                with_row_field(page, index, name, r, key, text)
                            ); }}
                        /> for (key, label, multiline) in ROW_FIELDS[name]
                    ]}
                    <Button
                        variant="ghost"
                        className="min-h-11 w-fit px-3"
                        onClick={lambda { on_page(
                            with_row_removed(page, index, name, r)
                        ); }}
                    >
                        {f"Remove this {ROW_NAMES[name]}"}
                    </Button>
                </div> for (r, row) in enumerate(rows)
            ]}
            {len(rows) < limit
                and <Button
                    variant="outline"
                    className="min-h-11 w-fit px-4"
                    onClick={lambda { on_page(with_row_added(page, index, name)); }}
                >
                    {f"Add {ROW_NAMES[name]}"}
                </Button>}
            <FieldError field_id={_id(index, name)} error={errors[base] or ""}/>
        </fieldset>;
}

def MovieChoices(  # jac:ignore[W3030] coming-soon movies: page, section, movies, limit, errors, handler
    page: dict[str, any],  # jac:ignore[W1037]
    index: int,
    movies: list[dict[str, str]],
    limit: int,
    errors: dict[str, str],
    on_page: any  # jac:ignore[W1037]
) -> JsxElement {
    chosen: list[str] = page["sections"][index]["fields"]["movie_ids"];
    base = f"sections.{index}.fields.movie_ids";
    return
        <fieldset className="flex flex-col gap-2">
            <legend className="mb-1 text-sm font-medium">
                {f"Movies to list (up to {limit})"}
            </legend>
            {len(movies) == 0
                and <p className="text-sm text-muted-foreground">
                    Add movies on the Movies page first.
                </p>}
            <div className="grid gap-2 sm:grid-cols-2">
                {[
                    <label key={m["movie_id"]} className={CHECK_ROW}>
                        <input
                            type="checkbox"
                            className="size-5"
                            checked={m["movie_id"] in chosen}
                            disabled={m["movie_id"] not in chosen
                                and len(chosen) >= limit}
                            onChange={lambda { on_page(
                                with_field(
                                    page,
                                    index,
                                    "movie_ids",
                                    toggled(chosen, m["movie_id"], limit)
                                )
                            ); }}
                        />
                        <span>{m["title"]}</span>
                    </label> for m in movies
                ]}
            </div>
            <FieldError field_id={_id(index, "movie_ids")} error={errors[base] or ""}/>
        </fieldset>;
}

def:pub PhotoChoices(  # jac:ignore[W3030] About photos: page, section, uploads, thumbnails, limit, errors, handlers
    page: dict[str, any],  # jac:ignore[W1037]
    index: int,
    photos: list[str],
    thumbs: dict[str, str],
    limit: int,
    errors: dict[str, str],
    busy: bool,
    on_page: any,  # jac:ignore[W1037]
    on_upload: any,  # jac:ignore[W1037]
    on_remove: any  # jac:ignore[W1037]
) -> JsxElement {
    chosen: list[str] = page["sections"][index]["fields"]["photos"];
    base = f"sections.{index}.fields.photos";
    return
        <fieldset className="flex flex-col gap-3">
            <legend className="mb-1 text-sm font-medium">
                {f"Photos to show (up to {limit})"}
            </legend>
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
                {[
                    <div
                        key={p}
                        data-testid="home-photo"
                        className="flex flex-col gap-2 rounded-lg border p-2"
                    >
                        <div
                            className="aspect-[4/3] overflow-hidden rounded-md bg-muted"
                        >
                            {thumbs[p]
                                and <img
                                    src={thumbs[p]}
                                    alt={f"Uploaded photo {i + 1}"}
                                    className="h-full w-full object-cover"
                                />}
                        </div>
                        <label
                            className="flex min-h-11 cursor-pointer items-center gap-2 text-sm"
                        >
                            <input
                                type="checkbox"
                                className="size-5"
                                checked={p in chosen}
                                disabled={p not in chosen and len(chosen) >= limit}
                                onChange={lambda { on_page(
                                    with_field(
                                        page, index, "photos", toggled(chosen, p, limit)
                                    )
                                ); }}
                            />
                            {f"Show photo {i + 1}"}
                        </label>
                        <Button
                            variant="ghost"
                            className="min-h-11 px-2"
                            disabled={busy}
                            onClick={lambda { on_remove(p); }}
                        >
                            {f"Delete photo {i + 1}"}
                        </Button>
                    </div> for (i, p) in enumerate(photos)
                ]}
            </div>
            <div className="flex flex-col gap-1.5">
                <Label htmlFor={_id(index, "photo-file")}>Upload a photo</Label>
                <input
                    id={_id(index, "photo-file")}
                    type="file"
                    accept="image/png,image/jpeg,image/webp"
                    disabled={busy}
                    onChange={on_upload}
                    className="min-h-11 text-sm file:mr-3 file:min-h-11 file:rounded-md file:border file:bg-card file:px-4 file:font-medium"
                />
                <p className="text-sm text-muted-foreground">
                    JPEG, PNG or WebP, at least 400 × 300 pixels, up to 5 MB.
                </p>
            </div>
            <FieldError field_id={_id(index, "photos")} error={errors[base] or ""}/>
        </fieldset>;
}

def:pub SectionFields(  # jac:ignore[W3030] one section's fields: page, section, options, errors and handlers
    page: dict[str, any],  # jac:ignore[W1037]
    index: int,
    options: dict[str, any],  # jac:ignore[W1037]
    errors: dict[str, str],
    on_page: any,  # jac:ignore[W1037]
    photo_editor: any = None  # jac:ignore[W1037] the About photos, drawn by the page
) -> JsxElement {
    section: dict[str, any] = page["sections"][index];  # jac:ignore[W1037]
    kind: str = section["type"];
    fields: dict[str, any] = section["fields"];  # jac:ignore[W1037]
    limits: dict[str, int] = options["limits"];
    movies: list[dict[str, str]] = options["movies"];
    base = f"sections.{index}.fields";

    def text(
        name: str, label: str, multiline: bool = False, hint: str = ""
    ) -> JsxElement {
        return
            <TextField
                field_id={_id(index, name)}
                label={label}
                value={fields[name]}
                multiline={multiline}
                hint={hint}
                error={errors[f"{base}.{name}"] or ""}
                on_value={lambda (value: str) { on_page(
                    with_field(page, index, name, value)
                ); }}
            />;
    }

    title = text("title", "Heading", hint="Leave empty to use the usual heading.");
    if kind == "hero" {
        return
            <div className="flex flex-col gap-4">
                {text(
                    "headline",
                    "Headline",
                    hint="Leave empty to show the movie's title."
                )}
                {text("text", "Short text", multiline=True)}
                <div className="flex flex-col gap-1.5">
                    <Label htmlFor={_id(index, "movie_id")}>Featured movie</Label>
                    <select
                        id={_id(index, "movie_id")}
                        value={fields["movie_id"]}
                        onChange={lambda (e: any) { on_page(  # jac:ignore[W1037]
                            with_field(page, index, "movie_id", e.target.value)
                        ); }}
                        className={SELECT_CLASSES}
                    >
                        <option value="">The next movie on sale</option>
                        {[
                            <option key={m["movie_id"]} value={m["movie_id"]}>
                                {m["title"]}
                            </option> for m in movies
                        ]}
                    </select>
                    <p className="text-sm text-muted-foreground">
                        Shown while it's on sale or listed as coming soon.
                    </p>
                    <FieldError
                        field_id={_id(index, "movie_id")}
                        error={errors[f"{base}.movie_id"] or ""}
                    />
                </div>
            </div>;
    }
    if kind == "coming_soon" {
        return
            <div className="flex flex-col gap-4">
                {title}
                <MovieChoices
                    page={page}
                    index={index}
                    movies={movies}
                    limit={limits["movie_ids"]}
                    errors={errors}
                    on_page={on_page}
                />
            </div>;
    }
    if kind == "about" {
        return
            <div className="flex flex-col gap-4">
                {title}{text("text", "Text", multiline=True)}{photo_editor}
            </div>;
    }
    if kind == "location" {
        return
            <div className="flex flex-col gap-4">
                {title}
                {text("address", "Address", multiline=True)}
                {text(
                    "map_url",
                    "Map link",
                    hint="A link to your cinema on a map, starting with https://"
                )}
                <RowList
                    page={page}
                    index={index}
                    name="hours"
                    legend="Opening hours"
                    limit={limits["hours"]}
                    errors={errors}
                    on_page={on_page}
                />
            </div>;
    }
    if kind == "contact" {
        return
            <div className="flex flex-col gap-4">
                {title}
                {text("phone", "Phone")}
                {text("email", "Email")}
                <RowList
                    page={page}
                    index={index}
                    name="links"
                    legend="Social and other links"
                    limit={limits["links"]}
                    errors={errors}
                    on_page={on_page}
                />
            </div>;
    }
    if kind == "faq" {
        return
            <div className="flex flex-col gap-4">
                {title}
                <RowList
                    page={page}
                    index={index}
                    name="items"
                    legend="Questions and answers"
                    limit={limits["faq_items"]}
                    errors={errors}
                    on_page={on_page}
                />
            </div>;
    }
    # Today and Now showing fill themselves from the programme.
    return <div className="flex flex-col gap-4">{title}</div>;
}
