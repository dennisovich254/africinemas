"""Movies and their posters (P3.4). Tenant-scoped endpoints, listed in
tests/isolation/registry.jac.

- Movies belong to the cinema, not to a venue. Reading needs movies.read, creating needs
  movies.create, and changing or deleting a movie or its poster needs movies.update.
- A poster is checked and re-encoded by core/catalog/poster.jac and stored under
  tenant/{tenant_id}/media/{uuid}.webp (architecture §56); the storage key never comes
  from the client. get_poster returns it as base64 WebP: a Jac endpoint can't send the
  image bytes themselves (JI-033).
- The new poster file is written before the request commits, and deleted again if the
  request fails; the old one is deleted once the change has committed.
- Another cinema's movie ids answer not_found.
"""

import io;
import base64;
import from uuid { uuid4 }
import from jaclang { JacRuntime as Jac }
import from datetime { date }
import from core.clock { now }
import from core.authz.context { NotFound, TenantScope, scoped }
import from core.tenancy.groups { attach_to_tenant }
import from core.tenancy.principal { node_id, act_as, restore, flush_now }
import from core.catalog.models { Movie }
import from core.catalog.answers { Refused, answer }
import from core.catalog.venues { screenings_of_movie }
import from core.catalog.storefront { PUBLIC_STATES, project }
import from core.catalog.poster {
    PosterRejected,
    decode_upload,
    process_poster,
    process_backdrop,
    media_key,
    media_store
}
import from core.audit.log { audited }
import from core.catalog.trailer { TrailerRejected, clean_trailer, trailer_embed }

glob READ: str = "movies.read",
     CREATE: str = "movies.create",
     UPDATE: str = "movies.update",
     TITLE_MAX: int = 120,
     SYNOPSIS_MAX: int = 2000,
     RUNTIME_MAX: int = 600,
     # Kenya Film Classification Board classes.
     RATINGS: list[str] = ["GE", "PG", "16", "18", "R"],
     GENRES_MAX: int = 5,
     GENRE_MAX: int = 30,
     LANGUAGE_MAX: int = 40;

def _clean(text: str) -> str {
    return " ".join(text.split());
}

def _release_date(text: str) -> str {
    # A release date as "YYYY-MM-DD", or "" for none. Raises Refused.
    cleaned = (text or "").strip();
    if not cleaned {
        return "";
    }
    refused = Refused(
        "invalid_release_date", "Enter the release date as a date, like 2026-12-18."
    );
    try {
        day = date.fromisoformat(cleaned);
    } except ValueError {
        raise refused;
    }
    if len(cleaned) != 10 or not 1900 <= day.year <= 2100 {
        raise refused;
    }
    return day.isoformat();
}

class MovieDetails {
    # Checked, tidied movie fields from a request.
    def init(
        self: MovieDetails,
        title: str,
        synopsis: str,
        runtime_minutes: int,
        age_rating: str,
        genres: list[str],
        language: str,
        release_date: str = ""
    ) {
        self.title = _clean(title);
        if not self.title or len(self.title) > TITLE_MAX {
            raise Refused(
                "invalid_title", f"Enter a title of 1 to {TITLE_MAX} characters."
            );
        }
        self.synopsis = synopsis.strip();
        if len(self.synopsis) > SYNOPSIS_MAX {
            raise Refused(
                "invalid_synopsis",
                f"Keep the synopsis to {SYNOPSIS_MAX} characters or fewer."
            );
        }
        if isinstance(runtime_minutes, bool)
            or not isinstance(runtime_minutes, int)
            or not 1 <= runtime_minutes <= RUNTIME_MAX {
            raise Refused(
                "invalid_runtime",
                f"Enter a running time of 1 to {RUNTIME_MAX} minutes."
            );
        }
        self.runtime_minutes = runtime_minutes;
        if age_rating not in RATINGS {
            raise Refused(
                "invalid_rating", f"Choose an age rating: {', '.join(RATINGS)}."
            );
        }
        self.age_rating = age_rating;
        cleaned = [_clean(g) for g in genres];
        if len(cleaned) > GENRES_MAX
            or any(not g or len(g) > GENRE_MAX for g in cleaned) {
            raise Refused(
                "invalid_genres",
                f"Give up to {GENRES_MAX} genres of 1 to {GENRE_MAX} characters each."
            );
        }
        self.genres = cleaned;
        self.language = _clean(language);
        if len(self.language) > LANGUAGE_MAX {
            raise Refused(
                "invalid_language", f"Keep the language to {LANGUAGE_MAX} characters."
            );
        }
        self.release_date = _release_date(release_date);
    }
}

def _view(m: Movie) -> dict[str, any] {  # jac:ignore[W1037]
    return {
        "movie_id": node_id(m),
        "title": m.title,
        "synopsis": m.synopsis,
        "runtime_minutes": m.runtime_minutes,
        "age_rating": m.age_rating,
        "genres": m.genres,
        "language": m.language,
        "has_poster": m.poster_key != "",
        "has_backdrop": m.backdrop_key != "",
        "release_date": m.release_date,
        "trailer_url": m.trailer_url,
        "trailer_embed": trailer_embed(m.trailer_url)
    };
}

def _find(scope: TenantScope, movie_id: str) -> Movie {
    # The caller's cinema's movie with this id, read as its principal.
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        found: any = jobj(movie_id) if movie_id else None;  # jac:ignore[W1037]
    } except Exception {
        found = None;
    } finally {
        restore(me);
    }
    if not isinstance(found, Movie) or found.tenant_id != scope.ctx.tenant_id {
        raise NotFound();
    }
    return found as Movie;
}

def _write(movie: Movie, details: MovieDetails) {
    movie.title = details.title;
    movie.synopsis = details.synopsis;
    movie.runtime_minutes = details.runtime_minutes;
    movie.age_rating = details.age_rating;
    movie.genres = details.genres;
    movie.language = details.language;
    movie.release_date = details.release_date;
    movie.updated_at = now().isoformat();
}

def _create_movie(  # jac:ignore[W3030] the new-movie form: cinema and its seven fields
    tenant: str,
    title: str,
    synopsis: str,
    runtime_minutes: int,
    age_rating: str,
    genres: list[str],
    language: str,
    release_date: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, CREATE);
    details = MovieDetails(
        title, synopsis, runtime_minutes, age_rating, genres, language, release_date
    );
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        movie = Movie(
            tenant_id=scope.ctx.tenant_id,
            title=details.title,
            created_at=now().isoformat()
        );
        _write(movie, details);
        scope.tenant ++> movie;
        attach_to_tenant(movie, scope.tenant);
        flush_now();
    } finally {
        restore(me);
    }
    return {"ok": True, "movie": _view(movie)};
}

def _list_movies(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, READ);
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        movies = [scope.tenant-->[?:Movie]];
    } finally {
        restore(me);
    }
    ordered = sorted(
        movies, key=lambda (m: Movie) -> str { return m.title.casefold(); }
    );  # jac:ignore[W1037]
    return {"ok": True, "movies": [_view(m) for m in ordered]};
}

def _get_movie(tenant: str, movie_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, READ);
    return {"ok": True, "movie": _view(_find(scope, movie_id))};
}

def _update_movie(  # jac:ignore[W3030] the edit form: cinema, movie and its seven fields
    tenant: str,
    movie_id: str,
    title: str,
    synopsis: str,
    runtime_minutes: int,
    age_rating: str,
    genres: list[str],
    language: str,
    release_date: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, UPDATE);
    movie = _find(scope, movie_id);
    details = MovieDetails(
        title, synopsis, runtime_minutes, age_rating, genres, language, release_date
    );
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        _write(movie, details);
        flush_now();
    } finally {
        restore(me);
    }
    _reproject(scope, movie_id);
    return {"ok": True, "movie": _view(movie)};
}

def _reproject(scope: TenantScope, movie_id: str) {
    # Published screenings of this movie show its details on the storefront (P3.5b).
    for screening in screenings_of_movie(scope.tenant, movie_id) {
        if screening.state in PUBLIC_STATES {
            project(scope.tenant, screening);
        }
    }
}

def _delete_movie(tenant: str, movie_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, UPDATE);
    movie = _find(scope, movie_id);
    # Screenings, even cancelled ones, are history that tickets and reports point at.
    if screenings_of_movie(scope.tenant, movie_id) {
        raise Refused(
            "movie_has_screenings", "This movie has screenings, so it can't be deleted."
        );
    }
    old_key = movie.poster_key;
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        Jac.destroy([movie]);
        flush_now();
    } finally {
        restore(me);
    }
    if old_key {
        on_commit(lambda { media_store().delete(old_key); });
    }
    return {"ok": True};
}

def _upload_poster(
    tenant: str, movie_id: str, content_type: str, data_base64: str
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, UPDATE);
    movie = _find(scope, movie_id);
    try {
        webp = process_poster(decode_upload(data_base64), content_type);
    } except PosterRejected as e {
        raise Refused(e.code, e.message);
    }
    new_key = media_key(scope.ctx.tenant_id, str(uuid4()));
    old_key = movie.poster_key;
    storage = media_store();
    storage.upload(io.BytesIO(webp), new_key);
    me = node_id(root);
    try {
        act_as(scope.tenant.principal_root_id);
        try {
            movie.poster_key = new_key;
            movie.updated_at = now().isoformat();
            flush_now();
        } finally {
            restore(me);
        }
    } except Exception as e {
        storage.delete(new_key);
        raise e;
    }
    if old_key {
        on_commit(lambda { media_store().delete(old_key); });
    }
    _reproject(scope, movie_id);
    return {"ok": True, "movie": _view(movie)};
}

def _set_backdrop(scope: TenantScope, movie: Movie, new_key: str) {
    # Points the movie at a new backdrop ("" for none), deleting the old file once the
    # request commits, and refreshes the storefront.
    old_key = movie.backdrop_key;
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        movie.backdrop_key = new_key;
        movie.updated_at = now().isoformat();
        flush_now();
    } finally {
        restore(me);
    }
    if old_key {
        on_commit(lambda { media_store().delete(old_key); });
    }
    _reproject(scope, node_id(movie));
}

def _upload_backdrop(
    tenant: str, movie_id: str, content_type: str, data_base64: str
) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, UPDATE);
    movie = _find(scope, movie_id);
    try {
        webp = process_backdrop(decode_upload(data_base64), content_type);
    } except PosterRejected as e {
        raise Refused(e.code, e.message);
    }
    new_key = media_key(scope.ctx.tenant_id, str(uuid4()));
    storage = media_store();
    storage.upload(io.BytesIO(webp), new_key);
    try {
        _set_backdrop(scope, movie, new_key);
    } except Exception as e {
        storage.delete(new_key);
        raise e;
    }
    return {"ok": True, "movie": _view(movie)};
}

def _remove_backdrop(tenant: str, movie_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, UPDATE);
    movie = _find(scope, movie_id);
    if movie.backdrop_key {
        _set_backdrop(scope, movie, "");
    }
    return {"ok": True, "movie": _view(movie)};
}

def _get_poster(tenant: str, movie_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    scope = scoped(tenant, READ);
    movie = _find(scope, movie_id);
    data = media_store().download(movie.poster_key) if movie.poster_key else None;
    if not data {
        raise Refused("no_poster", "This movie has no poster yet.");
    }
    return {
        "ok": True,
        "content_type": "image/webp",
        "data_base64": base64.b64encode(data).decode()
    };
}

def _do_create_movie(  # jac:ignore[W3030] the new-movie form: cinema and its seven fields
    tenant: str,
    title: str,
    synopsis: str,
    runtime_minutes: int,
    age_rating: str,
    genres: list[str],
    language: str,
    release_date: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(
        lambda -> any { return _create_movie(  # jac:ignore[W1037]
            tenant,
            title,
            synopsis,
            runtime_minutes,
            age_rating,
            genres,
            language,
            release_date
        ); }
    );
}

def:priv list_movies(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _list_movies(tenant); });  # jac:ignore[W1037]
}

def:priv get_movie(tenant: str, movie_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _get_movie(tenant, movie_id); });  # jac:ignore[W1037]
}

def _do_update_movie(  # jac:ignore[W3030] the edit form: cinema, movie and its seven fields
    tenant: str,
    movie_id: str,
    title: str,
    synopsis: str,
    runtime_minutes: int,
    age_rating: str,
    genres: list[str],
    language: str,
    release_date: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(
        lambda -> any { return _update_movie(  # jac:ignore[W1037]
            tenant,
            movie_id,
            title,
            synopsis,
            runtime_minutes,
            age_rating,
            genres,
            language,
            release_date
        ); }
    );
}

def _do_delete_movie(tenant: str, movie_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _delete_movie(tenant, movie_id); });  # jac:ignore[W1037]
}

def _set_trailer(tenant: str, movie_id: str, url: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The movie's trailer link (P8.1): a YouTube or Vimeo link, kept in canonical form;
    # "" clears it.
    scope = scoped(tenant, UPDATE);
    movie = _find(scope, movie_id);
    try {
        link = clean_trailer(url);
    } except TrailerRejected as e {
        raise Refused("invalid_trailer", str(e));
    }
    me = node_id(root);
    act_as(scope.tenant.principal_root_id);
    try {
        movie.trailer_url = link;
        movie.updated_at = now().isoformat();
        flush_now();
    } finally {
        restore(me);
    }
    # The storefront's copy of the movie gets the trailer too.
    _reproject(scope, movie_id);
    return {"ok": True, "movie": _view(movie)};
}

def _do_upload_poster(
    tenant: str, movie_id: str, content_type: str, data_base64: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(
        lambda -> any { return _upload_poster(  # jac:ignore[W1037]
            tenant, movie_id, content_type, data_base64
        ); }
    );
}

def:priv get_poster(tenant: str, movie_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _get_poster(tenant, movie_id); });  # jac:ignore[W1037]
}

def _do_upload_backdrop(
    tenant: str, movie_id: str, content_type: str, data_base64: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(
        lambda -> any { return _upload_backdrop(  # jac:ignore[W1037]
            tenant, movie_id, content_type, data_base64
        ); }
    );
}

def _do_remove_backdrop(tenant: str, movie_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _remove_backdrop(tenant, movie_id); });  # jac:ignore[W1037]
}

def:priv create_movie(  # jac:ignore[W3030] the new-movie form: cinema and its seven fields
    tenant: str,
    title: str,
    synopsis: str,
    runtime_minutes: int,
    age_rating: str,
    genres: list[str],
    language: str,
    release_date: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "movie.created",
        "movie",
        "",
        lambda -> any { return _do_create_movie(
            tenant,
            title,
            synopsis,
            runtime_minutes,
            age_rating,
            genres,
            language,
            release_date
        ); },
        made="movie.movie_id"  # jac:ignore[W1037]
    );
}

def:priv update_movie(  # jac:ignore[W3030] the edit form: cinema, movie and its seven fields
    tenant: str,
    movie_id: str,
    title: str,
    synopsis: str,
    runtime_minutes: int,
    age_rating: str,
    genres: list[str],
    language: str,
    release_date: str = ""
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "movie.updated",
        "movie",
        movie_id,
        lambda -> any { return _do_update_movie(
            tenant,
            movie_id,
            title,
            synopsis,
            runtime_minutes,
            age_rating,
            genres,
            language,
            release_date
        ); }  # jac:ignore[W1037]
    );
}

def:priv delete_movie(tenant: str, movie_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "movie.deleted",
        "movie",
        movie_id,
        lambda -> any { return _do_delete_movie(tenant, movie_id); }  # jac:ignore[W1037]
    );
}

def:priv upload_poster(
    tenant: str, movie_id: str, content_type: str, data_base64: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "movie.poster_uploaded",
        "movie",
        movie_id,
        lambda -> any { return _do_upload_poster(
            tenant, movie_id, content_type, data_base64
        ); }  # jac:ignore[W1037]
    );
}

def:priv upload_backdrop(
    tenant: str, movie_id: str, content_type: str, data_base64: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "movie.backdrop_uploaded",
        "movie",
        movie_id,
        lambda -> any { return _do_upload_backdrop(
            tenant, movie_id, content_type, data_base64
        ); }  # jac:ignore[W1037]
    );
}

def:priv remove_backdrop(tenant: str, movie_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "movie.backdrop_removed",
        "movie",
        movie_id,
        lambda -> any { return _do_remove_backdrop(tenant, movie_id); }  # jac:ignore[W1037]
    );
}

def:priv set_trailer(tenant: str, movie_id: str, url: str) -> dict[str, any] {  # jac:ignore[W1037]
    return audited(
        tenant,
        "movie.trailer_set",
        "movie",
        movie_id,
        lambda -> any { return answer(
            lambda -> any { return _set_trailer(tenant, movie_id, url); }
        ); }  # jac:ignore[W1037]
    );
}
