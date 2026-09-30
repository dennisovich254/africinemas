"""`/app/:slug/movies/new` and `/app/:slug/movies/:movie_id`: add or edit a movie (P3.7a).

Title, synopsis, running time, age rating (Kenya Film Classification Board classes),
genres and language. The running time is checked when the field is left, and every
server refusal is shown under the field it concerns. Once a movie exists it can get a
poster (checked and re-encoded on the server, P3.4) and be deleted, after a
confirmation; a movie with screenings can't be.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { useNavigate }
import from ..shell.AppLink { AppLink }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { ArrowLeft01Icon }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.button { Button }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.catalog.movie_api {
    create_movie,  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)
    get_movie,  # jac:ignore[W2037]
    update_movie,  # jac:ignore[W2037]
    delete_movie,  # jac:ignore[W2037]
    upload_poster  # jac:ignore[W2037]
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
import from .MoviesSection { PosterThumb, movie_path }

glob RATINGS: list[str] = ["GE", "PG", "16", "18", "R"],
     RUNTIME_MAX: int = 600,
     DIGITS: str = "0123456789",
     POSTER_TYPES: str = "image/png,image/jpeg,image/webp",
     SELECT_CLASSES: str = "min-h-11 w-full rounded-md border border-input bg-background px-3 text-sm",
     FIELDS: dict[str, str] = {
         "title": "movie-title",
         "synopsis": "movie-synopsis",
         "runtime": "movie-runtime",
         "rating": "movie-rating",
         "genres": "movie-genres",
         "language": "movie-language"
     },
     BLANK: dict[str, str] = {
         "title": "",
         "synopsis": "",
         "runtime": "",
         "rating": "",
         "genres": "",
         "language": ""
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

def form_from(movie: dict[str, any]) -> dict[str, str] {  # jac:ignore[W1037]
    return {
        "title": movie["title"],
        "synopsis": movie["synopsis"],
        "runtime": str(movie["runtime_minutes"]),
        "rating": movie["age_rating"],
        "genres": ", ".join(movie["genres"]),
        "language": movie["language"]
    };
}

def:pub MovieEditor(slug: str, movie_id: str) -> JsxElement {
    navigate: any = useNavigate();  # jac:ignore[W1037,W1051]
    is_new = movie_id == "new";
    [movie, set_movie] = useState(None);
    [form, set_form] = useState(BLANK);
    [errors, set_errors] = useState({});
    [failed, set_failed] = useState("");
    [busy, set_busy] = useState("");
    [message, set_message] = useState("");
    [confirming, set_confirming] = useState(False);
    # Bumped on each upload, so the poster preview fetches the new image.
    [poster_rev, set_poster_rev] = useState(0);

    async def load {
        answer: any = None;  # jac:ignore[W1037]
        if is_new {
            set_movie(None);
            set_form(BLANK);
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
        shown: dict[str, str] = {};
        for k in field_errors {
            if k != field_id {
                shown[k] = field_errors[k];
            }
        }
        if text {
            shown[field_id] = text;
        }
        set_errors(shown);
    }

    def check_runtime {
        set_error(FIELDS["runtime"], runtime_error(values["runtime"]));
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
                    values["language"]
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
                    values["language"]
                );
            }
        } except Exception as e {
            console.warn("saving the movie failed", e);
            set_busy("");
            set_message("We couldn't save. Check your connection and try again.");
            return;
        }
        set_busy("");
        if not answer["ok"] {
            target = field_for(answer["error"]["code"], FIELDS);
            if target {
                set_errors({target: answer["error"]["message"]});
            } else {
                set_message(answer["error"]["message"]);
            }
            return;
        }
        set_errors({});
        if is_new {
            navigate(movie_path(slug, answer["movie"]["movie_id"]));
            return;
        }
        set_movie(answer["movie"]);
        set_form(form_from(answer["movie"]));
        set_message("Saved.");
    }

    async def choose_poster(e: any) {  # jac:ignore[W1037]
        file: any = e.target.files[0];  # jac:ignore[W1037]
        answer: any = None;  # jac:ignore[W1037]
        if not file {
            return;
        }
        set_busy("poster");
        set_message("");
        set_error("poster-file", "");
        try {
            encoded = await read_as_base64(file);
            answer = await upload_poster(slug, movie_id, file.type, encoded);  # jac:ignore[W2037]
        } except Exception as err {
            console.warn("upload_poster failed", err);
            set_busy("");
            set_message("We couldn't upload that poster. Try again.");
            return;
        }
        e.target.value = "";
        set_busy("");
        if not answer["ok"] {
            set_error("poster-file", answer["error"]["message"]);
            return;
        }
        set_movie(answer["movie"]);
        set_poster_rev(poster_rev + 1);
        set_message("Poster saved.");
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
            <form
                className="grid gap-4 sm:grid-cols-2"
                noValidate={True}
                onSubmit={submit_with(lambda { save(); })}
            >
                <h2 className="text-xl font-semibold sm:col-span-2">
                    {"Add a movie" if is_new else values["title"] or "Movie"}
                </h2>
                <div className="sm:col-span-2">
                    <TextField
                        field_id={FIELDS["title"]}
                        label="Title"
                        value={values["title"]}
                        error={field_errors[FIELDS["title"]] or ""}
                        on_value={lambda (v: str) { change("title", v); }}
                    />
                </div>
                <div className="sm:col-span-2">
                    <TextField
                        field_id={FIELDS["synopsis"]}
                        label="Synopsis (optional)"
                        value={values["synopsis"]}
                        multiline={True}
                        error={field_errors[FIELDS["synopsis"]] or ""}
                        on_value={lambda (v: str) { change("synopsis", v); }}
                    />
                </div>
                <TextField
                    field_id={FIELDS["runtime"]}
                    label="Running time (minutes)"
                    value={values["runtime"]}
                    input_mode="numeric"
                    error={field_errors[FIELDS["runtime"]] or ""}
                    on_value={lambda (v: str) { change("runtime", v); }}
                    on_blur={check_runtime}
                />
                <div className="flex flex-col gap-1.5">
                    <Label htmlFor={FIELDS["rating"]}>Age rating</Label>
                    <select
                        id={FIELDS["rating"]}
                        value={values["rating"]}
                        aria-invalid={"true"
                            if field_errors[FIELDS["rating"]]
                            else "false"}
                        aria-describedby={error_id(FIELDS["rating"])
                            if field_errors[FIELDS["rating"]]
                            else None}
                        onChange={on_input(lambda (v: str) { change("rating", v); })}
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
                    on_value={lambda (v: str) { change("genres", v); }}
                />
                <TextField
                    field_id={FIELDS["language"]}
                    label="Language (optional)"
                    value={values["language"]}
                    error={field_errors[FIELDS["language"]] or ""}
                    on_value={lambda (v: str) { change("language", v); }}
                />
                <div className="flex flex-wrap items-center gap-3 sm:col-span-2">
                    <Button
                        type="submit"
                        className="min-h-11 px-5"
                        disabled={busy != ""}
                    >
                        {busy == "saving" and <Spinner aria-hidden="true"/>}{"Add movie"
                            if is_new
                            else "Save changes"}
                    </Button>
                </div>
            </form>
            <p role="status" aria-live="polite" className="text-sm">{message}</p>
            {current is not None
                and <section
                    aria-labelledby="poster-heading"
                    className="flex flex-col gap-3"
                >
                    <h3 id="poster-heading" className="font-semibold">Poster</h3>
                    <div className="flex flex-wrap items-end gap-4">
                        {current["has_poster"]
                            and <span data-testid="poster">
                                <PosterThumb
                                    key={poster_rev}
                                    slug={slug}
                                    movie={current}
                                    size="w-28"
                                />
                            </span>}
                        <div className="flex min-w-0 flex-col gap-1.5">
                            <Label htmlFor="poster-file">
                                {"Replace the poster"
                                    if current["has_poster"]
                                    else "Upload a poster"}
                            </Label>
                            <input
                                id="poster-file"
                                type="file"
                                accept={POSTER_TYPES}
                                disabled={busy != ""}
                                aria-describedby={"poster-file-error"
                                    if field_errors["poster-file"]
                                    else "poster-hint"}
                                onChange={choose_poster}
                                className="min-h-11 max-w-full text-sm file:mr-3 file:min-h-11 file:rounded-md file:border file:bg-card file:px-4 file:font-medium"
                            />
                            <p
                                id="poster-hint"
                                className="text-sm text-muted-foreground"
                            >
                                PNG, JPEG or WebP, at least 200 × 300 pixels, up to 5 MB. Portrait works best.
                            </p>
                            {field_errors["poster-file"]
                                and <FieldError
                                    field_id="poster-file"
                                    error={field_errors["poster-file"]}
                                />}
                        </div>
                    </div>
                </section>}
            {current is not None
                and <section
                    aria-labelledby="delete-heading"
                    className="flex flex-col gap-3"
                >
                    <h3 id="delete-heading" className="font-semibold">
                        Delete this movie
                    </h3>
                    {not confirming
                        and <Button
                            variant="outline"
                            className="min-h-11 w-fit px-5"
                            disabled={busy != ""}
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
                            busy={busy != ""}
                        />}
                </section>}
        </div>;
}
