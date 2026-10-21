"""`/app/:slug/movies/new` and `/app/:slug/movies/:movie_id`: add or edit a movie (P3.7a).

One page, the same for a new movie and an existing one (improvements #5, #6, #9):
Details (title, synopsis), Showing facts (running time, age rating from the Kenya Film
Classification Board classes, genres, language, release date) and the Trailer link on
the left; the Poster (2:3) and Backdrop (16:9) beside them, each with a preview, chosen
by clicking or dropping a file. A new movie takes all of it at once: Add movie creates
it, then uploads the chosen images and saves the trailer. On an existing movie a chosen
image uploads at once, and Save changes saves the details and the trailer.

The running time is checked when the field is left, and every server refusal is shown
under the field it concerns. Images are checked and re-encoded on the server (P3.4). A
movie can be deleted after a confirmation; one with screenings can't be.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { useNavigate, useLocation }
import from ..shell.AppLink { AppLink }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { ArrowLeft01Icon }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.button { Button }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.catalog.movie_api {
    create_movie,  # jac:ignore[W2037] authenticated endpoint
    get_movie,  # jac:ignore[W2037]
    update_movie,  # jac:ignore[W2037]
    delete_movie,  # jac:ignore[W2037]
    upload_poster,  # jac:ignore[W2037]
    get_poster,  # jac:ignore[W2037]
    get_backdrop,  # jac:ignore[W2037]
    upload_backdrop,  # jac:ignore[W2037]
    remove_backdrop,  # jac:ignore[W2037]
    set_trailer  # jac:ignore[W2037]
}
import from .form_parts {
    TextField,
    FieldError,
    ConfirmDelete,
    field_for,
    error_id,
    on_input,
    submit_with,
    read_as_base64
}
import from .MoviesSection { movie_path }

glob RATINGS: list[str] = ["GE", "PG", "16", "18", "R"],
     RUNTIME_MAX: int = 600,
     DIGITS: str = "0123456789",
     POSTER_TYPES: str = "image/png,image/jpeg,image/webp",
     MEDIA_MAX_BYTES: int = 5 * 1024 * 1024,
     SELECT_CLASSES: str = "min-h-11 w-full rounded-md border border-input bg-background px-3 text-sm",
     FIELDS: dict[str, str] = {
         "title": "movie-title",
         "synopsis": "movie-synopsis",
         "runtime": "movie-runtime",
         "rating": "movie-rating",
         "genres": "movie-genres",
         "language": "movie-language",
         "release_date": "movie-release-date"
     },
     BLANK: dict[str, str] = {
         "title": "",
         "synopsis": "",
         "runtime": "",
         "rating": "",
         "genres": "",
         "language": "",
         "release_date": ""
     };

def:pub runtime_error(text: str) -> str {
    # "" when `text` is a whole number of minutes the server accepts.
    cleaned = text.strip();
    if not cleaned {
        return "Enter the running time in minutes.";
    }
    for ch in cleaned {
        if ch not in DIGITS {
            return "Enter the running time as a whole number of minutes, like 95.";
        }
    }
    minutes = int(cleaned);
    if minutes < 1 or minutes > RUNTIME_MAX {
        return f"Enter a running time of 1 to {RUNTIME_MAX} minutes.";
    }
    return "";
}

def:pub genre_list(text: str) -> list[str] {
    # "Drama, Romance" -> ["Drama", "Romance"]
    found: list[str] = [];
    for part in text.split(",") {
        if part.strip() {
            found.append(part.strip());
        }
    }
    return found;
}

def:pub media_problem(file: any) -> str {  # jac:ignore[W1037]
    # "" when the chosen file is an image type and size the server takes.
    if file.type not in POSTER_TYPES.split(",") {
        return "Choose a PNG, JPEG or WebP image.";
    }
    if file.size > MEDIA_MAX_BYTES {
        return "Choose an image of 5 MB or less.";
    }
    return "";
}

def Card(title: str, children: any = None) -> JsxElement {  # jac:ignore[W1037]
    return
        <section className="flex flex-col gap-4 rounded-xl border bg-card p-5">
            <h3 className="font-semibold">{title}</h3>
            {children}
        </section>;
}

def MediaPicker(  # jac:ignore[W3030] an image field: ids, labels, preview and handlers
    field_id: str,
    title: str,
    hint: str,
    aspect: str,
    src: str,
    busy: bool,
    locked: bool,
    error: str,
    testid: str,
    on_file: any,  # jac:ignore[W1037]
    on_remove: any = None  # jac:ignore[W1037]
) -> JsxElement {
    # A poster or backdrop: its preview (or an empty frame), and a file chosen by
    # clicking the frame or dropping a file on it. `busy`: this image is uploading;
    # `locked`: anything is being saved, so nothing new can be chosen.
    def dropped(e: any) {  # jac:ignore[W1037]
        e.preventDefault();
        if not locked and len(e.dataTransfer.files) > 0 {
            on_file(e.dataTransfer.files[0]);
        }
    }

    def picked(e: any) {  # jac:ignore[W1037]
        if len(e.target.files) > 0 {
            on_file(e.target.files[0]);
        }
        e.target.value = "";
    }

    return
        <Card title={title}>
            <label
                htmlFor={field_id}
                onDragOver={lambda (e: any) { e.preventDefault(); }}  # jac:ignore[W1037]
                onDrop={dropped}
                className={f"relative flex {aspect} w-full cursor-pointer items-center justify-center overflow-hidden rounded-lg border border-dashed bg-muted text-center hover:border-foreground/40"}
            >
                {src
                    and <span data-testid={testid} className="absolute inset-0">
                        <img
                            src={src}
                            alt={f"{title} preview"}
                            className="size-full object-cover"
                        />
                    </span>}{not src
                    and <span
                        className="flex flex-col gap-1 px-4 text-sm text-muted-foreground"
                    >
                        <span className="font-medium text-foreground">
                            Choose an image
                        </span>
                        or drop one here
                    </span>}{busy
                    and <span
                        className="absolute inset-0 flex items-center justify-center gap-2 bg-background/70 text-sm"
                    >
                        <Spinner aria-hidden="true"/>
                        Uploading…
                    </span>}
            </label>
            <input
                id={field_id}
                type="file"
                accept={POSTER_TYPES}
                disabled={locked}
                aria-label={f"{'Replace' if src else 'Choose'} the {title.lower()}"}
                aria-describedby={error_id(field_id) if error else f"{field_id}-hint"}
                onChange={picked}
                className="sr-only"
            />
            <p id={f"{field_id}-hint"} className="text-sm text-muted-foreground">
                {hint}
            </p>
            {error and <FieldError field_id={field_id} error={error}/>}
            <div className="flex flex-wrap gap-2">
                <Button asChild={True} variant="outline" className="min-h-11">
                    <label htmlFor={field_id} className="cursor-pointer">
                        {f"Replace {title.lower()}"
                            if src
                            else f"Choose {title.lower()}"}
                    </label>
                </Button>
                {src
                    and on_remove is not None
                    and <Button
                        type="button"
                        variant="ghost"
                        className="min-h-11"
                        disabled={locked}
                        onClick={on_remove}
                    >
                        Remove
                    </Button>}
            </div>
        </Card>;
}

def form_from(movie: dict[str, any]) -> dict[str, str] {  # jac:ignore[W1037]
    return {
        "title": movie["title"],
        "synopsis": movie["synopsis"],
        "runtime": str(movie["runtime_minutes"]),
        "rating": movie["age_rating"],
        "genres": ", ".join(movie["genres"]),
        "language": movie["language"],
        "release_date": movie.get("release_date", "") or ""
    };
}

def:pub MovieEditor(slug: str, movie_id: str) -> JsxElement {
    navigate: any = useNavigate();  # jac:ignore[W1037,W1051]
    location: any = useLocation();  # jac:ignore[W1037,W1051]
    is_new = movie_id == "new";
    [movie, set_movie] = useState(None);
    [form, set_form] = useState(BLANK);
    [errors, set_errors] = useState({});
    [failed, set_failed] = useState("");
    [busy, set_busy] = useState("");
    [message, set_message] = useState("");
    [confirming, set_confirming] = useState(False);
    [trailer_text, set_trailer_text] = useState("");
    # What each image frame shows: the saved image, or the file just chosen.
    [poster_src, set_poster_src] = useState("");
    [backdrop_src, set_backdrop_src] = useState("");
    # A new movie's chosen images, uploaded once Add movie has made it.
    [poster_file, set_poster_file] = useState(None);
    [backdrop_file, set_backdrop_file] = useState(None);

    async def load_art(kind: str) {
        # The saved poster or backdrop of this movie, as a data URL.
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await (
                get_poster(slug, movie_id)  # jac:ignore[W2037]
                    if kind == "poster"
                    else get_backdrop(slug, movie_id)  # jac:ignore[W2037]
            );
        } except Exception as e {
            console.warn(f"loading the {kind} failed", e);
            return;
        }
        shown = f"data:{answer['content_type']};base64,{answer['data_base64']}"
            if answer["ok"]
            else "";
        if kind == "poster" {
            set_poster_src(shown);
        } else {
            set_backdrop_src(shown);
        }
    }

    async def load {
        answer: any = None;  # jac:ignore[W1037]
        if is_new {
            set_movie(None);
            set_form(BLANK);
            set_trailer_text("");
            set_poster_src("");
            set_backdrop_src("");
            return;
        }
        try {
            answer = await get_movie(slug, movie_id);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("get_movie failed", e);
            set_failed("We couldn't load this movie. Refresh the page to try again.");
            return;
        }
        if not answer["ok"] {
            set_failed("This movie doesn't exist, or it isn't your cinema's.");
            return;
        }
        set_movie(answer["movie"]);
        set_form(form_from(answer["movie"]));
        set_trailer_text(answer["movie"].get("trailer_url", "") or "");
        # What Add movie left to say, carried here with the navigation.
        carried: any = location.state;  # jac:ignore[W1037]
        if carried and carried["notice"] {
            set_message(carried["notice"]);
            set_errors(carried["left"] or {});
        }
        if answer["movie"]["has_poster"] {
            load_art("poster");
        } else {
            set_poster_src("");
        }
        if answer["movie"]["has_backdrop"] {
            load_art("backdrop");
        } else {
            set_backdrop_src("");
        }
    }
    def start_loading {
        load();
    }
    useEffect(start_loading, [slug, movie_id]);

    values: dict[str, str] = form;
    field_errors: dict[str, str] = errors;

    def change(key: str, value: str) {
        next_form: dict[str, str] = {};
        for k in values {
            next_form[k] = values[k];
        }
        next_form[key] = value;
        set_form(next_form);
        set_message("");
    }

    def set_error(field_id: str, text: str) {
        set_errors(
            lambda (prev: dict[str, str]) -> dict[str, str] {
                shown: dict[str, str] = {};
                for k in prev {
                    if k != field_id {
                        shown[k] = prev[k];
                    }
                }
                if text {
                    shown[field_id] = text;
                }
                return shown;
            }
        );
    }

    def check_runtime {
        set_error(FIELDS["runtime"], runtime_error(values["runtime"]));
    }

    async def send_image(kind: str, target: str, file: any) -> str {  # jac:ignore[W1037]
        # Uploads `file` as movie `target`'s poster or backdrop: "" when it's taken,
        # else why not.
        answer: any = None;  # jac:ignore[W1037]
        try {
            encoded = await read_as_base64(file);
            answer = await (
                upload_poster(slug, target, file.type, encoded)  # jac:ignore[W2037]
                    if kind == "poster"
                    else upload_backdrop(slug, target, file.type, encoded)  # jac:ignore[W2037]
            );
        } except Exception as err {
            console.warn(f"uploading the {kind} failed", err);
            return f"We couldn't upload that {kind}. Try again.";
        }
        if not answer["ok"] {
            return answer["error"]["message"];
        }
        set_movie(answer["movie"]);
        return "";
    }

    async def choose_image(kind: str, file: any) {  # jac:ignore[W1037]
        # Shows the chosen image at once; on an existing movie it's uploaded now.
        field_id = f"{kind}-file";
        problem = media_problem(file);
        set_error(field_id, problem);
        set_message("");
        if problem {
            return;
        }
        win: any = window;  # jac:ignore[W1037,W2001]
        preview = win.URL.createObjectURL(file);
        if kind == "poster" {
            set_poster_src(preview);
        } else {
            set_backdrop_src(preview);
        }
        if is_new {
            if kind == "poster" {
                set_poster_file(file);
            } else {
                set_backdrop_file(file);
            }
            return;
        }
        set_busy(kind);
        refused = await send_image(kind, movie_id, file);
        set_busy("");
        if refused {
            set_error(field_id, refused);
            load_art(kind);
        } else {
            set_message("Poster saved." if kind == "poster" else "Backdrop saved.");
        }
    }

    async def drop_backdrop {
        answer: any = None;  # jac:ignore[W1037]
        if is_new {
            set_backdrop_file(None);
            set_backdrop_src("");
            return;
        }
        set_busy("backdrop");
        try {
            answer = await remove_backdrop(slug, movie_id);  # jac:ignore[W2037]
        } except Exception as err {
            console.warn("remove_backdrop failed", err);
            set_busy("");
            set_message("We couldn't remove the backdrop. Try again.");
            return;
        }
        set_busy("");
        if answer["ok"] {
            set_movie(answer["movie"]);
            set_backdrop_src("");
            set_message("Backdrop removed.");
        }
    }

    def drop_new_poster {
        set_poster_file(None);
        set_poster_src("");
    }

    async def send_trailer(target: str, link: str) -> str {
        # Saves movie `target`'s trailer link ("" removes it): "" when it's taken.
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await set_trailer(slug, target, link);  # jac:ignore[W2037]
        } except Exception as err {
            console.warn("set_trailer failed", err);
            return "We couldn't save the trailer. Try again.";
        }
        if not answer["ok"] {
            return answer["error"]["message"];
        }
        set_movie(answer["movie"]);
        set_trailer_text(answer["movie"]["trailer_url"]);
        return "";
    }

    async def save {
        answer: any = None;  # jac:ignore[W1037]
        problem = runtime_error(values["runtime"]);
        if problem {
            set_error(FIELDS["runtime"], problem);
            return;
        }
        minutes = int(values["runtime"].strip());
        genres = genre_list(values["genres"]);
        set_busy("saving");
        set_message("");
        try {
            if is_new {
                answer = await create_movie(  # jac:ignore[W2037]
                    slug,
                    values["title"],
                    values["synopsis"],
                    minutes,
                    values["rating"],
                    genres,
                    values["language"],
                    values["release_date"]
                );
            } else {
                answer = await update_movie(  # jac:ignore[W2037]
                    slug,
                    movie_id,
                    values["title"],
                    values["synopsis"],
                    minutes,
                    values["rating"],
                    genres,
                    values["language"],
                    values["release_date"]
                );
            }
        } except Exception as e {
            console.warn("saving the movie failed", e);
            set_busy("");
            set_message("We couldn't save. Check your connection and try again.");
            return;
        }
        if not answer["ok"] {
            set_busy("");
            target = field_for(answer["error"]["code"], FIELDS);
            if target {
                set_errors({target: answer["error"]["message"]});
            } else {
                set_message(answer["error"]["message"]);
            }
            return;
        }
        set_errors({});
        made: str = answer["movie"]["movie_id"];
        link = trailer_text.strip();
        # What wasn't saved, by field.
        left: dict[str, str] = {};
        if is_new {
            # The movie exists now: its images and trailer follow (improvements #9).
            if poster_file is not None {
                why = await send_image("poster", made, poster_file);
                if why {
                    left["poster-file"] = why;
                }
            }
            if backdrop_file is not None {
                why = await send_image("backdrop", made, backdrop_file);
                if why {
                    left["backdrop-file"] = why;
                }
            }
            if link {
                why = await send_trailer(made, link);
                if why {
                    left["trailer-url"] = why;
                }
            }
            set_busy("");
            set_poster_file(None);
            set_backdrop_file(None);
            # The editor starts afresh on the new movie's page: say how it went there.
            notice = "Movie added."
                if len(left) == 0
                else "Movie added, but some of it wasn't saved: see below, and try again here.";
            navigate(
                movie_path(slug, made), {"state": {"notice": notice, "left": left}}
            );
            return;
        }
        set_movie(answer["movie"]);
        set_form(form_from(answer["movie"]));
        known = answer["movie"].get("trailer_url", "") or "";
        why = await send_trailer(movie_id, link) if link != known else "";
        set_busy("");
        if why {
            set_error("trailer-url", why);
            set_message("Saved, but the trailer wasn't: see below.");
        } else {
            set_message("Saved.");
        }
    }

    async def remove {
        answer: any = None;  # jac:ignore[W1037]
        set_confirming(False);
        set_busy("deleting");
        try {
            answer = await delete_movie(slug, movie_id);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("delete_movie failed", e);
        }
        set_busy("");
        if answer and answer["ok"] {
            navigate(f"/app/{slug}/movies");
            return;
        }
        set_message(
            answer["error"]["message"]
                if answer
                else "We couldn't delete this movie. Try again."
        );
    }

    if failed {
        return
            <Alert variant="destructive">
                <AlertDescription>{failed}</AlertDescription>
            </Alert>;
    }
    if not is_new and movie is None {
        return
            <p role="status" className="flex items-center gap-2 text-muted-foreground">
                <Spinner aria-hidden="true"/>
                Loading the movie…
            </p>;
    }
    current: dict[str, any] | None = movie;  # jac:ignore[W1037]
    working = busy != "";

    details = <Card title="Details">
        <TextField
            field_id={FIELDS["title"]}
            label="Title"
            value={values["title"]}
            error={field_errors[FIELDS["title"]] or ""}
            on_value={lambda (text: str) { change("title", text); }}
        />
        <TextField
            field_id={FIELDS["synopsis"]}
            label="Synopsis (optional)"
            value={values["synopsis"]}
            multiline={True}
            hint="A sentence or two for your storefront."
            error={field_errors[FIELDS["synopsis"]] or ""}
            on_value={lambda (text: str) { change("synopsis", text); }}
        />
    </Card>;

    facts = <Card title="Showing facts">
        <div className="grid gap-4 sm:grid-cols-2">
            <TextField
                field_id={FIELDS["runtime"]}
                label="Running time (minutes)"
                value={values["runtime"]}
                input_mode="numeric"
                error={field_errors[FIELDS["runtime"]] or ""}
                on_value={lambda (text: str) { change("runtime", text); }}
                on_blur={check_runtime}
            />
            <div className="flex flex-col gap-1.5">
                <Label htmlFor={FIELDS["rating"]}>Age rating</Label>
                <select
                    id={FIELDS["rating"]}
                    value={values["rating"]}
                    aria-invalid={"true" if field_errors[FIELDS["rating"]] else "false"}
                    aria-describedby={error_id(FIELDS["rating"])
                        if field_errors[FIELDS["rating"]]
                        else None}
                    onChange={on_input(lambda (text: str) { change("rating", text); })}
                    className={SELECT_CLASSES}
                >
                    <option value="">Choose a rating</option>
                    {[<option key={r} value={r}>{r}</option> for r in RATINGS]}
                </select>
                {field_errors[FIELDS["rating"]]
                    and <FieldError
                        field_id={FIELDS["rating"]}
                        error={field_errors[FIELDS["rating"]]}
                    />}
            </div>
            <TextField
                field_id={FIELDS["genres"]}
                label="Genres (optional)"
                value={values["genres"]}
                hint="Separate them with commas, up to 5."
                error={field_errors[FIELDS["genres"]] or ""}
                on_value={lambda (text: str) { change("genres", text); }}
            />
            <TextField
                field_id={FIELDS["language"]}
                label="Language (optional)"
                value={values["language"]}
                error={field_errors[FIELDS["language"]] or ""}
                on_value={lambda (text: str) { change("language", text); }}
            />
            <div className="flex min-w-0 flex-col gap-1.5">
                <Label htmlFor={FIELDS["release_date"]}>Release date (optional)</Label>
                <input
                    id={FIELDS["release_date"]}
                    type="date"
                    value={values["release_date"]}
                    aria-invalid={"true"
                        if field_errors[FIELDS["release_date"]]
                        else "false"}
                    aria-describedby={"movie-release-date-error"
                        if field_errors[FIELDS["release_date"]]
                        else "movie-release-date-hint"}
                    onChange={on_input(
                        lambda (text: str) { change("release_date", text); }
                    )}
                    className="min-h-11 w-full rounded-md border border-input bg-background px-3 text-sm"
                />
                <p
                    id="movie-release-date-hint"
                    className="text-sm text-muted-foreground"
                >
                    Shown on your storefront, for example under Coming soon.
                </p>
                {field_errors[FIELDS["release_date"]]
                    and <FieldError
                        field_id={FIELDS["release_date"]}
                        error={field_errors[FIELDS["release_date"]]}
                    />}
            </div>
        </div>
    </Card>;

    trailer = <Card title="Trailer (optional)">
        <div className="flex min-w-0 flex-col gap-1.5">
            <Label htmlFor="trailer-url">Trailer link</Label>
            <input
                id="trailer-url"
                type="url"
                inputMode="url"
                placeholder="https://www.youtube.com/watch?v=…"
                value={trailer_text}
                disabled={working}
                aria-describedby={"trailer-url-error"
                    if field_errors["trailer-url"]
                    else "trailer-url-hint"}
                onChange={lambda (e: any) { set_trailer_text(e.target.value); }}  # jac:ignore[W1037]
                className="min-h-11 w-full rounded-md border border-input bg-background px-3 text-sm"
            />
            <p id="trailer-url-hint" className="text-sm text-muted-foreground">
                A YouTube or Vimeo link. Customers can watch it on your storefront and in the AI chat. It's saved with the movie.
            </p>
            {field_errors["trailer-url"]
                and <FieldError
                    field_id="trailer-url"
                    error={field_errors["trailer-url"]}
                />}
        </div>
    </Card>;

    poster = <MediaPicker
        field_id="poster-file"
        title="Poster"
        hint="Portrait, PNG, JPEG or WebP, at least 200 × 300 pixels, up to 5 MB."
        aspect="aspect-[2/3]"
        src={poster_src}
        busy={busy == "poster"}
        locked={working}
        error={field_errors["poster-file"] or ""}
        testid="poster"
        on_file={lambda (f: any) { choose_image("poster", f); }}  # jac:ignore[W1037]
        on_remove={drop_new_poster if is_new else None}
    />;

    backdrop = <MediaPicker
        field_id="backdrop-file"
        title="Backdrop"
        hint="Landscape, at least 960 × 540 pixels, up to 5 MB. Shown across your storefront when this movie is featured; without one, the poster is used, blurred."
        aspect="aspect-video"
        src={backdrop_src}
        busy={busy == "backdrop"}
        locked={working}
        error={field_errors["backdrop-file"] or ""}
        testid="backdrop-set"
        on_file={lambda (f: any) { choose_image("backdrop", f); }}  # jac:ignore[W1037]
        on_remove={drop_backdrop}
    />;

    return
        <div className="flex flex-col gap-6" data-testid="movie-form">
            <AppLink
                to={f"/app/{slug}/movies"}
                className="inline-flex min-h-11 w-fit items-center gap-1 text-sm font-medium text-muted-foreground hover:text-foreground"
            >
                <HugeiconsIcon
                    icon={ArrowLeft01Icon}
                    strokeWidth={2}
                    aria-hidden="true"
                />
                Movies
            </AppLink>
            <h2 className="text-2xl font-semibold">
                {"Add a movie" if is_new else values["title"] or "Movie"}
            </h2>
            <form
                noValidate={True}
                onSubmit={submit_with(lambda { save(); })}
                className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_20rem]"
            >
                <div className="flex min-w-0 flex-col gap-6">
                    {details}{facts}{trailer}
                </div>
                <aside className="flex flex-col gap-6 lg:sticky lg:top-6 lg:self-start">
                    {poster}{backdrop}
                </aside>
                <div
                    className="sticky bottom-0 z-10 -mx-1 flex flex-wrap items-center gap-3 border-t bg-background/95 px-1 py-3 backdrop-blur lg:col-span-2"
                >
                    <Button type="submit" className="min-h-11 px-6" disabled={working}>
                        {busy == "saving" and <Spinner aria-hidden="true"/>}{"Add movie"
                            if is_new
                            else "Save changes"}
                    </Button>
                    <Button asChild={True} variant="ghost" className="min-h-11">
                        <AppLink to={f"/app/{slug}/movies"}>Cancel</AppLink>
                    </Button>
                    <p role="status" aria-live="polite" className="text-sm">
                        {message}
                    </p>
                </div>
            </form>
            {current is not None
                and <section
                    aria-labelledby="delete-heading"
                    className="flex flex-col gap-3 rounded-xl border border-destructive/30 p-5"
                >
                    <h3 id="delete-heading" className="font-semibold">
                        Delete this movie
                    </h3>
                    <p className="text-sm text-muted-foreground">
                        Its poster and backdrop are deleted too. Movies with screenings can't be deleted.
                    </p>
                    {not confirming
                        and <Button
                            variant="outline"
                            className="min-h-11 w-fit px-5"
                            disabled={working}
                            onClick={lambda { set_confirming(True); }}
                        >
                            Delete movie
                        </Button>}
                    {confirming
                        and <ConfirmDelete
                            question={f"Delete {current['title']}?"}
                            detail="Its poster is deleted too. Movies with screenings can't be deleted."
                            confirm_label={f"Delete {current['title']}"}
                            on_confirm={remove}
                            on_cancel={lambda { set_confirming(False); }}
                            busy={working}
                        />}
                </section>}
        </div>;
}
